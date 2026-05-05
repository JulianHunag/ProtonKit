import Foundation
import CommonCrypto
import Security
import ObjectivePGP

public struct EncryptedAttachment {
    public let sessionKey: Data
    public let dataPacket: Data
}

public enum AttachmentCrypto {

    public static func encrypt(data: Data) throws -> EncryptedAttachment {
        var sessionKey = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &sessionKey) == errSecSuccess else {
            throw EncryptionError.encryptionFailed("Failed to generate session key")
        }
        let keyData = Data(sessionKey)

        var litBody = Data()
        litBody.append(0x62)
        litBody.append(0x00)
        litBody.append(contentsOf: [0, 0, 0, 0])
        litBody.append(data)
        let literalPacket = ClearBodyEncryptor.buildPacket(tag: 11, body: litBody)

        let seipdBody = try buildSEIPD(content: literalPacket, sessionKey: keyData)
        let seipdPacket = ClearBodyEncryptor.buildPacket(tag: 18, body: seipdBody)

        return EncryptedAttachment(sessionKey: keyData, dataPacket: seipdPacket)
    }

    public static func buildKeyPacket(sessionKey: Data, armoredPublicKey: String) throws -> Data {
        guard let keyData = armoredPublicKey.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("Invalid key encoding")
        }
        let keys = try ObjectivePGP.readKeys(from: keyData)
        guard !keys.isEmpty else {
            throw EncryptionError.encryptionFailed("No keys found")
        }

        let exported = try keys[0].export()
        let (keyID, n, e) = try findEncryptionSubkey(exported)

        var block = Data()
        block.append(9) // AES-256
        block.append(sessionKey)
        let checksum: UInt16 = sessionKey.reduce(0) { $0 &+ UInt16($1) }
        block.append(UInt8(checksum >> 8))
        block.append(UInt8(checksum & 0xFF))

        let encrypted = try rsaEncrypt(data: block, n: n, e: e)

        var body = Data()
        body.append(3) // version 3
        body.append(keyID)
        body.append(1) // RSA
        appendMPI(encrypted, to: &body)

        return ClearBodyEncryptor.buildPacket(tag: 1, body: body)
    }

    // MARK: - PGP key parsing

    private static func findEncryptionSubkey(_ data: Data) throws -> (keyID: Data, n: Data, e: Data) {
        var offset = 0
        var primaryKey: (keyID: Data, n: Data, e: Data)?

        while offset < data.count {
            guard let (tag, headerLen, bodyLen) = parsePacketHeader(data, offset: offset) else { break }
            let bodyStart = offset + headerLen
            let bodyEnd = bodyStart + bodyLen
            guard bodyEnd <= data.count else { break }

            if tag == 6 || tag == 14 {
                if let parsed = parseRSAKeyPacket(Data(data[bodyStart..<bodyEnd])) {
                    if tag == 14 { return parsed }
                    primaryKey = parsed
                }
            }
            offset = bodyEnd
        }

        if let pk = primaryKey { return pk }
        throw EncryptionError.encryptionFailed("No RSA key found in public key")
    }

    private static func parseRSAKeyPacket(_ data: Data) -> (keyID: Data, n: Data, e: Data)? {
        guard data.count > 6, data[0] == 4 else { return nil }
        let algo = data[5]
        guard algo == 1 || algo == 2 || algo == 3 else { return nil }

        var pos = 6
        guard let (n, nEnd) = readMPI(data, offset: pos) else { return nil }
        pos = nEnd
        guard let (e, _) = readMPI(data, offset: pos) else { return nil }

        var hashInput = Data()
        hashInput.append(0x99)
        hashInput.append(UInt8(data.count >> 8))
        hashInput.append(UInt8(data.count & 0xFF))
        hashInput.append(data)
        let hash = sha1(hashInput)
        let keyID = Data(hash.suffix(8))

        return (keyID, n, e)
    }

    private static func readMPI(_ data: Data, offset: Int) -> (value: Data, endOffset: Int)? {
        guard offset + 2 <= data.count else { return nil }
        let bitLen = Int(data[offset]) << 8 | Int(data[offset + 1])
        let byteLen = (bitLen + 7) / 8
        let start = offset + 2
        guard start + byteLen <= data.count else { return nil }
        return (Data(data[start..<start + byteLen]), start + byteLen)
    }

    private static func appendMPI(_ data: Data, to output: inout Data) {
        var bitLen = 0
        for (i, byte) in data.enumerated() {
            if byte != 0 {
                bitLen = (data.count - i) * 8 - byte.leadingZeroBitCount
                break
            }
        }
        if bitLen == 0 { bitLen = 1 }
        output.append(UInt8(bitLen >> 8))
        output.append(UInt8(bitLen & 0xFF))
        if let start = data.firstIndex(where: { $0 != 0 }) {
            output.append(data[start...])
        } else {
            output.append(0)
        }
    }

    // MARK: - RSA

    private static func rsaEncrypt(data: Data, n: Data, e: Data) throws -> Data {
        let derKey = buildDERPublicKey(n: n, e: e)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let secKey = SecKeyCreateWithData(derKey as CFData, attributes as CFDictionary, &error) else {
            throw EncryptionError.encryptionFailed("Failed to create RSA key")
        }

        guard let encrypted = SecKeyCreateEncryptedData(secKey, .rsaEncryptionPKCS1, data as CFData, &error) else {
            throw EncryptionError.encryptionFailed("RSA encryption failed")
        }

        return encrypted as Data
    }

    private static func buildDERPublicKey(n: Data, e: Data) -> Data {
        let nDER = derInteger(n)
        let eDER = derInteger(e)
        return derSequence(nDER + eDER)
    }

    private static func derInteger(_ data: Data) -> Data {
        var result = Data()
        result.append(0x02)
        var value = data
        if let first = value.first, first & 0x80 != 0 {
            value.insert(0x00, at: 0)
        }
        result.append(contentsOf: derLength(value.count))
        result.append(value)
        return result
    }

    private static func derSequence(_ content: Data) -> Data {
        var result = Data()
        result.append(0x30)
        result.append(contentsOf: derLength(content.count))
        result.append(content)
        return result
    }

    private static func derLength(_ length: Int) -> [UInt8] {
        if length < 0x80 { return [UInt8(length)] }
        if length <= 0xFF { return [0x81, UInt8(length)] }
        return [0x82, UInt8(length >> 8), UInt8(length & 0xFF)]
    }

    // MARK: - Packet parsing

    private static func parsePacketHeader(_ data: Data, offset: Int) -> (tag: UInt8, headerLen: Int, bodyLen: Int)? {
        guard offset < data.count else { return nil }
        let header = data[offset]
        guard header & 0x80 != 0 else { return nil }

        if header & 0x40 != 0 {
            let tag = header & 0x3F
            var pos = offset + 1
            guard pos < data.count else { return nil }
            let first = data[pos]
            let bodyLen: Int
            if first < 192 {
                bodyLen = Int(first); pos += 1
            } else if first < 224 {
                guard pos + 1 < data.count else { return nil }
                bodyLen = (Int(first) - 192) << 8 + Int(data[pos + 1]) + 192; pos += 2
            } else if first == 255 {
                guard pos + 4 < data.count else { return nil }
                bodyLen = Int(data[pos+1]) << 24 | Int(data[pos+2]) << 16 | Int(data[pos+3]) << 8 | Int(data[pos+4]); pos += 5
            } else {
                return (tag, 2, data.count - offset - 2)
            }
            return (tag, pos - offset, bodyLen)
        } else {
            let tag = (header & 0x3C) >> 2
            let lenType = header & 0x03
            var pos = offset + 1
            let bodyLen: Int
            switch lenType {
            case 0:
                guard pos < data.count else { return nil }
                bodyLen = Int(data[pos]); pos += 1
            case 1:
                guard pos + 1 < data.count else { return nil }
                bodyLen = Int(data[pos]) << 8 | Int(data[pos+1]); pos += 2
            case 2:
                guard pos + 3 < data.count else { return nil }
                bodyLen = Int(data[pos]) << 24 | Int(data[pos+1]) << 16 | Int(data[pos+2]) << 8 | Int(data[pos+3]); pos += 4
            default:
                return (tag, 1, data.count - offset - 1)
            }
            return (tag, pos - offset, bodyLen)
        }
    }

    // MARK: - Crypto helpers

    private static func buildSEIPD(content: Data, sessionKey: Data) throws -> Data {
        let blockSize = kCCBlockSizeAES128
        var prefix = [UInt8](repeating: 0, count: blockSize + 2)
        guard SecRandomCopyBytes(kSecRandomDefault, blockSize, &prefix) == errSecSuccess else {
            throw EncryptionError.encryptionFailed("Failed to generate random prefix")
        }
        prefix[blockSize] = prefix[blockSize - 2]
        prefix[blockSize + 1] = prefix[blockSize - 1]
        let prefixData = Data(prefix)

        var toHash = Data()
        toHash.append(prefixData)
        toHash.append(content)
        toHash.append(contentsOf: [0xD3, 0x14])
        let hash = sha1(toHash)

        var mdcPacket = Data([0xD3, 0x14])
        mdcPacket.append(hash)

        var plaintext = Data()
        plaintext.append(prefixData)
        plaintext.append(content)
        plaintext.append(mdcPacket)

        let encrypted = try aesCFBEncrypt(key: sessionKey, plaintext: plaintext)

        var body = Data([0x01])
        body.append(encrypted)
        return body
    }

    private static func aesCFBEncrypt(key: Data, plaintext: Data) throws -> Data {
        var cryptorRef: CCCryptorRef?
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)
        let createStatus = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            CCCryptorCreateWithMode(
                CCOperation(kCCEncrypt), CCMode(kCCModeCFB),
                CCAlgorithm(kCCAlgorithmAES), CCPadding(ccNoPadding),
                iv, keyPtr.baseAddress, key.count,
                nil, 0, 0, CCModeOptions(0), &cryptorRef
            )
        }
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else {
            throw EncryptionError.encryptionFailed("AES-CFB init failed")
        }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var updateLen = 0
        let updateStatus = output.withUnsafeMutableBytes { outPtr in
            plaintext.withUnsafeBytes { inPtr in
                CCCryptorUpdate(cryptor, inPtr.baseAddress, plaintext.count,
                    outPtr.baseAddress, outPtr.count, &updateLen)
            }
        }
        guard updateStatus == kCCSuccess else {
            throw EncryptionError.encryptionFailed("AES-CFB update failed")
        }
        var finalLen = 0
        let finalStatus = output.withUnsafeMutableBytes { outPtr in
            CCCryptorFinal(cryptor, outPtr.baseAddress?.advanced(by: updateLen),
                outPtr.count - updateLen, &finalLen)
        }
        guard finalStatus == kCCSuccess else {
            throw EncryptionError.encryptionFailed("AES-CFB final failed")
        }
        return output.prefix(updateLen + finalLen)
    }

    private static func sha1(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA1_DIGEST_LENGTH))
        data.withUnsafeBytes { ptr in
            _ = CC_SHA1(ptr.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }
}
