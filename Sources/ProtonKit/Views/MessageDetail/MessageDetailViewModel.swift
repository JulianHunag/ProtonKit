import SwiftUI
import ProtonCore

private struct CachedMessage {
    let message: FullMessage
    let bodyHTML: String
    let rawDecryptedBody: String
}

@MainActor
final class MessageDetailViewModel: ObservableObject {
    @Published var message: FullMessage?
    @Published var bodyHTML: String = ""
    @Published var rawDecryptedBody: String = ""
    @Published var isLoading = false
    @Published var errorMessage: String?

    private static var cache: [String: CachedMessage] = [:]

    func load(client: ProtonClient, messageID: String, decryptor: MessageDecryptor? = nil) async {
        if let cached = Self.cache[messageID] {
            message = cached.message
            bodyHTML = cached.bodyHTML
            rawDecryptedBody = cached.rawDecryptedBody
            try? await MessageAPI.markRead(client: client, messageIDs: [messageID])
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let resp = try await MessageAPI.get(client: client, messageID: messageID)
            message = resp.message

            if let decryptor, resp.message.body.contains("-----BEGIN PGP MESSAGE-----") {
                do {
                    let decrypted = try decryptor.decrypt(armoredMessage: resp.message.body)
                    rawDecryptedBody = decrypted
                    bodyHTML = HTMLSanitizer.sanitize(decrypted)
                } catch {
                    ProtonClient.debugLog("Decryption failed: \(error)")
                    bodyHTML = "<pre style='color:red'>Decryption error: \(error.localizedDescription)</pre><hr><pre>\(resp.message.body.prefix(200))...</pre>"
                }
            } else {
                bodyHTML = HTMLSanitizer.sanitize(resp.message.body)
            }

            Self.cache[messageID] = CachedMessage(message: resp.message, bodyHTML: bodyHTML, rawDecryptedBody: rawDecryptedBody)

            try? await MessageAPI.markRead(client: client, messageIDs: [messageID])
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    static func invalidate(_ messageID: String) {
        cache.removeValue(forKey: messageID)
    }
}
