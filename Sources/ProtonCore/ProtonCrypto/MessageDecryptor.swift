import Foundation
import ObjectivePGP

public enum DecryptionError: Error, LocalizedError {
    case noKeys
    case keyParseFailed
    case decryptionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .noKeys: return "No decryption keys available"
        case .keyParseFailed: return "Failed to parse PGP private key"
        case .decryptionFailed(let msg): return "Decryption failed: \(msg)"
        }
    }
}

public final class MessageDecryptor {
    private var allKeys: [Key] = []
    private var passphraseMap: [ObjectIdentifier: String] = [:]

    public init() {}

    public func loadKeysWithPassphrases(_ keyPassphrases: [(armoredKey: String, passphrase: String)]) throws {
        allKeys = []
        passphraseMap = [:]
        for (armored, passphrase) in keyPassphrases {
            guard let data = armored.data(using: .utf8) else { continue }
            if let parsed = try? ObjectivePGP.readKeys(from: data) {
                for key in parsed {
                    allKeys.append(key)
                    passphraseMap[ObjectIdentifier(key)] = passphrase
                }
            }
        }
        guard !allKeys.isEmpty else { throw DecryptionError.keyParseFailed }
    }

    public func loadKeys(armoredPrivateKeys: [String], passphrase: String) throws {
        try loadKeysWithPassphrases(armoredPrivateKeys.map { ($0, passphrase) })
    }

    public static func decryptToken(_ armoredToken: String, userArmoredKey: String, userPassphrase: String) -> String? {
        guard let keyData = userArmoredKey.data(using: .utf8) else {
            debugLog("decryptToken: userKey data encoding failed")
            return nil
        }

        let userKeys: [Key]
        do {
            userKeys = try ObjectivePGP.readKeys(from: keyData)
        } catch {
            debugLog("decryptToken: readKeys failed: \(error)")
            return nil
        }
        guard !userKeys.isEmpty else {
            debugLog("decryptToken: no user keys parsed")
            return nil
        }
        debugLog("decryptToken: parsed \(userKeys.count) user keys")

        guard let tokenData = armoredToken.data(using: .utf8) else {
            debugLog("decryptToken: token data encoding failed")
            return nil
        }
        debugLog("decryptToken: token length=\(armoredToken.count), starts with: \(String(armoredToken.prefix(60)))")

        do {
            let decrypted = try ObjectivePGP.decrypt(
                tokenData,
                andVerifySignature: false,
                using: userKeys,
                passphraseForKey: { _ in userPassphrase }
            )
            debugLog("decryptToken: decrypt OK, result \(decrypted.count) bytes")
            if let result = String(data: decrypted, encoding: .utf8) {
                debugLog("decryptToken: passphrase length=\(result.count)")
                return result
            }
            debugLog("decryptToken: result is not valid UTF-8")
            return nil
        } catch {
            debugLog("decryptToken: decrypt FAILED: \(error)")
            return nil
        }
    }

    private static func debugLog(_ msg: String) {
        let url = URL(fileURLWithPath: "/tmp/pk_debug.log")
        let line = "\(Date()): [CRYPTO] \(msg)\n"
        guard let d = line.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            if let fh = try? FileHandle(forWritingTo: url) { fh.seekToEndOfFile(); fh.write(d); fh.closeFile() }
        } else { try? d.write(to: url) }
    }

    public func decrypt(armoredMessage: String) throws -> String {
        guard !allKeys.isEmpty else { throw DecryptionError.noKeys }

        guard let messageData = armoredMessage.data(using: .utf8) else {
            throw DecryptionError.decryptionFailed("Invalid message encoding")
        }

        let map = self.passphraseMap
        do {
            let decrypted = try ObjectivePGP.decrypt(
                messageData,
                andVerifySignature: false,
                using: allKeys,
                passphraseForKey: { key in key.flatMap { map[ObjectIdentifier($0)] } }
            )
            if let text = String(data: decrypted, encoding: .utf8) {
                return text
            }
            return String(data: decrypted, encoding: .ascii) ?? ""
        } catch {
            throw DecryptionError.decryptionFailed(error.localizedDescription)
        }
    }
}
