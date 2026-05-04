import SwiftUI
import ProtonCore

enum ComposeMode: Identifiable {
    case reply(FullMessage)
    case replyAll(FullMessage)
    case newMessage

    var id: String {
        switch self {
        case .reply(let msg): return "reply-\(msg.id)"
        case .replyAll(let msg): return "replyAll-\(msg.id)"
        case .newMessage: return "new"
        }
    }
}

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var toText = ""
    @Published var ccText = ""
    @Published var subject = ""
    @Published var bodyText = ""
    @Published var isSending = false
    @Published var errorMessage: String?
    @Published var didSend = false

    let mode: ComposeMode
    private let originalMessage: FullMessage?

    init(mode: ComposeMode) {
        self.mode = mode
        switch mode {
        case .reply(let msg):
            self.originalMessage = msg
            self.toText = msg.senderAddress
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .replyAll(let msg):
            self.originalMessage = msg
            self.toText = msg.senderAddress
            self.ccText = msg.ccList.map(\.address).joined(separator: ", ")
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .newMessage:
            self.originalMessage = nil
        }
    }

    func send(session: SessionManager) async {
        guard !toText.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "No recipients specified"
            return
        }
        guard let account = session.accountStore.activeAccount,
              let address = account.addresses.first,
              let primaryKey = address.primaryKey else {
            errorMessage = "No sender address available"
            return
        }

        isSending = true
        errorMessage = nil

        do {
            let encryptor = MessageEncryptor()
            let passphrase = account.keyPassphrase ?? ""
            try encryptor.loadSenderKeys([(armoredKey: primaryKey.privateKey, passphrase: passphrase)])

            let htmlBody = bodyText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\n", with: "<br>")
            let wrappedBody = "<html><body>\(htmlBody)</body></html>"

            let encryptedDraftBody = try encryptor.encryptForDraft(plaintext: wrappedBody)

            let toAddresses = parseRecipients(toText)
            let ccAddresses = parseRecipients(ccText)

            var action: Int? = nil
            var parentID: String? = nil
            switch mode {
            case .reply(let msg):
                parentID = msg.id
                action = 0
            case .replyAll(let msg):
                parentID = msg.id
                action = 1
            case .newMessage:
                break
            }

            let draftResp = try await MessageAPI.createDraft(
                client: session.client,
                subject: subject,
                body: encryptedDraftBody,
                senderAddressID: address.id,
                senderName: account.displayName,
                senderAddress: address.email,
                toList: toAddresses,
                ccList: ccAddresses,
                parentID: parentID,
                action: action
            )
            let draftID = draftResp.message.id

            let allRecipients = toAddresses + ccAddresses
            var packages: [SendPackage] = []

            for recipient in allRecipients {
                let keyResp = try await KeyAPI.getPublicKeys(client: session.client, email: recipient.address)
                guard let pubKey = keyResp.keys.first?.publicKey else {
                    throw EncryptionError.recipientKeyParseFailed(recipient.address)
                }
                let split = try encryptor.encryptForRecipient(
                    plaintext: wrappedBody,
                    recipientArmoredPublicKey: pubKey
                )
                packages.append(SendPackage(
                    addresses: [recipient.address: SendAddress(
                        type: 1,
                        bodyKeyPacket: split.keyPacket.base64EncodedString()
                    )],
                    mimeType: "text/html",
                    body: split.dataPacket.base64EncodedString(),
                    type: 1
                ))
            }

            let _ = try await MessageAPI.sendMessage(
                client: session.client,
                messageID: draftID,
                packages: packages
            )

            didSend = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSending = false
    }

    private func parseRecipients(_ text: String) -> [EmailAddress] {
        text.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { EmailAddress(address: String($0)) }
    }

    private static func buildQuotedBody(_ msg: FullMessage) -> String {
        let date = Date(timeIntervalSince1970: msg.time)
            .formatted(.dateTime.year().month().day().hour().minute())
        return "\n\n--- On \(date), \(msg.senderName) wrote ---\n"
    }
}
