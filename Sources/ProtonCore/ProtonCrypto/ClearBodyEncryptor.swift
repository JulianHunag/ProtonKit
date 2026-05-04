import Foundation
import CommonCrypto

public struct EncryptedClearBody {
    public let sessionKey: Data
    public let algorithm: String
    public let dataPacket: Data
}

public enum ClearBodyEncryptor {

    public static func encryptSignedContent(_ signedData: Data) throws -> EncryptedClearBody {
        var sessionKey = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, 32, &sessionKey) == errSecSuccess else {
            throw EncryptionError.encryptionFailed("Failed to generate session key")
        }
        let keyData = Data(sessionKey)

        let compressedPacket = buildCompressedPacket(signedData, algorithm: 0)
        let seipdBody = try buildSEIPD(content: compressedPacket, sessionKey: keyData)
        let seipdPacket = buildPacket(tag: 18, body: seipdBody)

        return EncryptedClearBody(sessionKey: keyData, algorithm: "aes256", dataPacket: seipdPacket)
    }

    // MARK: - Packet builders

    private static func buildLiteralDataPacket(_ data: Data) -> Data {
        var body = Data()
        body.append(0x62) // 'b' = binary
        body.append(0x00) // filename length = 0
        body.append(contentsOf: [0, 0, 0, 0]) // timestamp = 0
        body.append(data)
        return buildPacket(tag: 11, body: body)
    }

    private static func buildCompressedPacket(_ data: Data, algorithm: UInt8) -> Data {
        var body = Data()
        body.append(algorithm)
        body.append(data)
        return buildPacket(tag: 8, body: body)
    }

    private static func buildSEIPD(content: Data, sessionKey: Data) throws -> Data {
        let blockSize = kCCBlockSizeAES128 // 16

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

        var seipdBody = Data([0x01]) // version
        seipdBody.append(encrypted)
        return seipdBody
    }

    // MARK: - Crypto

    private static func aesCFBEncrypt(key: Data, plaintext: Data) throws -> Data {
        var cryptorRef: CCCryptorRef?
        let iv = [UInt8](repeating: 0, count: kCCBlockSizeAES128)

        let createStatus = key.withUnsafeBytes { keyPtr -> CCCryptorStatus in
            CCCryptorCreateWithMode(
                CCOperation(kCCEncrypt),
                CCMode(kCCModeCFB),
                CCAlgorithm(kCCAlgorithmAES),
                CCPadding(ccNoPadding),
                iv,
                keyPtr.baseAddress, key.count,
                nil, 0, 0,
                CCModeOptions(0),
                &cryptorRef
            )
        }
        guard createStatus == kCCSuccess, let cryptor = cryptorRef else {
            throw EncryptionError.encryptionFailed("AES-CFB init failed: \(createStatus)")
        }
        defer { CCCryptorRelease(cryptor) }

        var output = Data(count: plaintext.count + kCCBlockSizeAES128)
        var updateLen = 0
        let updateStatus = output.withUnsafeMutableBytes { outPtr in
            plaintext.withUnsafeBytes { inPtr in
                CCCryptorUpdate(
                    cryptor,
                    inPtr.baseAddress, plaintext.count,
                    outPtr.baseAddress, outPtr.count,
                    &updateLen
                )
            }
        }
        guard updateStatus == kCCSuccess else {
            throw EncryptionError.encryptionFailed("AES-CFB update failed: \(updateStatus)")
        }

        var finalLen = 0
        let finalStatus = output.withUnsafeMutableBytes { outPtr in
            CCCryptorFinal(
                cryptor,
                outPtr.baseAddress?.advanced(by: updateLen), outPtr.count - updateLen,
                &finalLen
            )
        }
        guard finalStatus == kCCSuccess else {
            throw EncryptionError.encryptionFailed("AES-CFB final failed: \(finalStatus)")
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

    // MARK: - OpenPGP packet encoding

    static func buildPacket(tag: UInt8, body: Data) -> Data {
        var packet = Data()
        packet.append(0xC0 | tag) // new format
        encodeNewFormatLength(body.count, into: &packet)
        packet.append(body)
        return packet
    }

    private static func encodeNewFormatLength(_ length: Int, into data: inout Data) {
        if length < 192 {
            data.append(UInt8(length))
        } else if length < 8384 {
            let adjusted = length - 192
            data.append(UInt8((adjusted >> 8) + 192))
            data.append(UInt8(adjusted & 0xFF))
        } else {
            data.append(0xFF)
            data.append(UInt8((length >> 24) & 0xFF))
            data.append(UInt8((length >> 16) & 0xFF))
            data.append(UInt8((length >> 8) & 0xFF))
            data.append(UInt8(length & 0xFF))
        }
    }
}
