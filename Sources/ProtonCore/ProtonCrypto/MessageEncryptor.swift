import Foundation
import ObjectivePGP

public enum EncryptionError: Error, LocalizedError {
    case noSenderKey
    case encryptionFailed(String)
    case recipientKeyParseFailed(String)
    case packetSplitFailed

    public var errorDescription: String? {
        switch self {
        case .noSenderKey: return "No sender key available"
        case .encryptionFailed(let msg): return "Encryption failed: \(msg)"
        case .recipientKeyParseFailed(let email): return "Failed to parse public key for \(email)"
        case .packetSplitFailed: return "Failed to split PGP message packets"
        }
    }
}

public struct SplitMessage {
    public let keyPacket: Data
    public let dataPacket: Data
}

public final class MessageEncryptor {
    private var senderKeys: [Key] = []
    private var passphraseMap: [ObjectIdentifier: String] = [:]

    public init() {}

    public func loadSenderKeys(_ keyPassphrases: [(armoredKey: String, passphrase: String)]) throws {
        senderKeys = []
        passphraseMap = [:]
        for (armored, passphrase) in keyPassphrases {
            guard let data = armored.data(using: .utf8) else { continue }
            if let parsed = try? ObjectivePGP.readKeys(from: data) {
                for key in parsed {
                    senderKeys.append(key)
                    passphraseMap[ObjectIdentifier(key)] = passphrase
                }
            }
        }
        guard !senderKeys.isEmpty else { throw EncryptionError.noSenderKey }
    }

    public func encryptForDraft(plaintext: String, armoredPublicKey: String) throws -> String {
        guard let keyData = armoredPublicKey.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("Invalid public key encoding")
        }
        let pubKeys = try ObjectivePGP.readKeys(from: keyData)
        guard !pubKeys.isEmpty else { throw EncryptionError.noSenderKey }
        guard let data = plaintext.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("Invalid text encoding")
        }
        let encrypted = try ObjectivePGP.encrypt(
            data,
            addSignature: false,
            using: pubKeys,
            passphraseForKey: { _ in nil }
        )
        return Armor.armored(encrypted, as: .message)
    }

    public func encryptForRecipient(plaintext: String, recipientArmoredPublicKey: String) throws -> SplitMessage {
        guard let keyData = recipientArmoredPublicKey.data(using: .utf8) else {
            throw EncryptionError.recipientKeyParseFailed("unknown")
        }
        let recipientKeys = try ObjectivePGP.readKeys(from: keyData)
        guard !recipientKeys.isEmpty else {
            throw EncryptionError.recipientKeyParseFailed("unknown")
        }

        guard let bodyData = plaintext.data(using: .utf8) else {
            throw EncryptionError.encryptionFailed("Invalid text encoding")
        }

        let encrypted = try ObjectivePGP.encrypt(
            bodyData,
            addSignature: false,
            using: recipientKeys,
            passphraseForKey: { _ in nil }
        )

        return try splitPGPMessage(encrypted)
    }

    private func splitPGPMessage(_ data: Data) throws -> SplitMessage {
        var offset = 0
        var keyPacketData = Data()

        while offset < data.count {
            let packetStart = offset
            guard let (tag, totalLen) = parsePacketHeader(data, offset: offset) else {
                throw EncryptionError.packetSplitFailed
            }

            if tag == 1 {
                keyPacketData.append(data[packetStart..<packetStart + totalLen])
                offset = packetStart + totalLen
            } else {
                let dataPacket = Data(data[packetStart...])
                return SplitMessage(keyPacket: keyPacketData, dataPacket: dataPacket)
            }
        }
        throw EncryptionError.packetSplitFailed
    }

    private func parsePacketHeader(_ data: Data, offset: Int) -> (tag: UInt8, totalLength: Int)? {
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
                bodyLen = Int(first)
                pos += 1
            } else if first < 224 {
                guard pos + 1 < data.count else { return nil }
                bodyLen = (Int(first) - 192) << 8 + Int(data[pos + 1]) + 192
                pos += 2
            } else if first == 255 {
                guard pos + 4 < data.count else { return nil }
                bodyLen = Int(data[pos + 1]) << 24 | Int(data[pos + 2]) << 16 | Int(data[pos + 3]) << 8 | Int(data[pos + 4])
                pos += 5
            } else {
                // Partial body length - treat rest as this packet
                return (tag, data.count - offset)
            }
            return (tag, pos - offset + bodyLen)
        } else {
            let tag = (header & 0x3C) >> 2
            let lenType = header & 0x03
            var pos = offset + 1
            let bodyLen: Int
            switch lenType {
            case 0:
                guard pos < data.count else { return nil }
                bodyLen = Int(data[pos])
                pos += 1
            case 1:
                guard pos + 1 < data.count else { return nil }
                bodyLen = Int(data[pos]) << 8 | Int(data[pos + 1])
                pos += 2
            case 2:
                guard pos + 3 < data.count else { return nil }
                bodyLen = Int(data[pos]) << 24 | Int(data[pos + 1]) << 16 | Int(data[pos + 2]) << 8 | Int(data[pos + 3])
                pos += 4
            default:
                return (tag, data.count - offset)
            }
            return (tag, pos - offset + bodyLen)
        }
    }
}
