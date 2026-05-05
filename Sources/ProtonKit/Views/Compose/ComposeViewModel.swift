import SwiftUI
import ProtonCore

enum ComposeMode: Identifiable {
    case reply(FullMessage)
    case replyAll(FullMessage)
    case forward(FullMessage)
    case newMessage
    case editDraft(FullMessage, decryptedHTML: String)

    var id: String {
        switch self {
        case .reply(let msg): return "reply-\(msg.id)"
        case .replyAll(let msg): return "replyAll-\(msg.id)"
        case .forward(let msg): return "forward-\(msg.id)"
        case .newMessage: return "new"
        case .editDraft(let msg, _): return "editDraft-\(msg.id)"
        }
    }
}

struct ComposeAttachment: Identifiable {
    let id = UUID()
    let url: URL
    let data: Data
    var fileName: String { url.lastPathComponent }
    var mimeType: String {
        switch url.pathExtension.lowercased() {
        case "pdf": return "application/pdf"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "txt": return "text/plain"
        case "html", "htm": return "text/html"
        case "zip": return "application/zip"
        case "doc": return "application/msword"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xls": return "application/vnd.ms-excel"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        default: return "application/octet-stream"
        }
    }
}

@MainActor
final class ComposeViewModel: ObservableObject {
    @Published var toText = ""
    @Published var ccText = ""
    @Published var subject = ""
    @Published var bodyText = ""
    @Published var attachments: [ComposeAttachment] = []
    @Published var isSending = false
    @Published var isSavingDraft = false
    @Published var errorMessage: String?
    @Published var didSend = false
    @Published var didSaveDraft = false

    let mode: ComposeMode
    private let originalMessage: FullMessage?
    private let existingDraftID: String?

    init(mode: ComposeMode) {
        self.mode = mode
        switch mode {
        case .reply(let msg):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.toText = msg.senderAddress
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .replyAll(let msg):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.toText = msg.senderAddress
            self.ccText = msg.ccList.map(\.address).joined(separator: ", ")
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .forward(let msg):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.subject = msg.subject.hasPrefix("Fwd: ") ? msg.subject : "Fwd: \(msg.subject)"
            self.bodyText = Self.buildForwardBody(msg)
        case .newMessage:
            self.originalMessage = nil
            self.existingDraftID = nil
        case .editDraft(let msg, let decryptedHTML):
            self.originalMessage = msg
            self.existingDraftID = msg.id
            self.toText = msg.toList.map(\.address).joined(separator: ", ")
            self.ccText = msg.ccList.map(\.address).joined(separator: ", ")
            self.subject = msg.subject
            self.bodyText = Self.htmlToPlainText(decryptedHTML)
        }
    }

    func addAttachments(urls: [URL]) {
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                attachments.append(ComposeAttachment(url: url, data: data))
            }
        }
    }

    func removeAttachment(_ attachment: ComposeAttachment) {
        attachments.removeAll { $0.id == attachment.id }
    }

    func saveDraft(session: SessionManager) async {
        guard let account = session.accountStore.activeAccount,
              let address = account.addresses.first else {
            errorMessage = "No sender address available"
            return
        }

        isSavingDraft = true
        errorMessage = nil

        do {
            let (encryptedBody, _) = try await encryptBody(session: session, address: address)
            let toAddresses = parseRecipients(toText)
            let ccAddresses = parseRecipients(ccText)

            if let draftID = existingDraftID {
                let _ = try await MessageAPI.updateDraft(
                    client: session.client,
                    messageID: draftID,
                    subject: subject,
                    body: encryptedBody,
                    senderAddressID: address.id,
                    senderName: account.displayName,
                    senderAddress: address.email,
                    toList: toAddresses,
                    ccList: ccAddresses
                )
            } else {
                let (parentID, action) = replyParams()
                let _ = try await MessageAPI.createDraft(
                    client: session.client,
                    subject: subject,
                    body: encryptedBody,
                    senderAddressID: address.id,
                    senderName: account.displayName,
                    senderAddress: address.email,
                    toList: toAddresses,
                    ccList: ccAddresses,
                    parentID: parentID,
                    action: action
                )
            }
            didSaveDraft = true
        } catch {
            errorMessage = error.localizedDescription
        }

        isSavingDraft = false
    }

    func send(session: SessionManager) async {
        guard !toText.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "No recipients specified"
            return
        }
        guard let account = session.accountStore.activeAccount,
              let address = account.addresses.first else {
            errorMessage = "No sender address available"
            return
        }

        isSending = true
        errorMessage = nil

        do {
            let (encryptedDraftBody, wrappedBody) = try await encryptBody(session: session, address: address)
            let toAddresses = parseRecipients(toText)
            let ccAddresses = parseRecipients(ccText)

            let draftID: String
            if let existing = existingDraftID {
                let resp = try await MessageAPI.updateDraft(
                    client: session.client,
                    messageID: existing,
                    subject: subject,
                    body: encryptedDraftBody,
                    senderAddressID: address.id,
                    senderName: account.displayName,
                    senderAddress: address.email,
                    toList: toAddresses,
                    ccList: ccAddresses
                )
                draftID = resp.message.id
            } else {
                let (parentID, action) = replyParams()
                let resp = try await MessageAPI.createDraft(
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
                draftID = resp.message.id
            }

            if !attachments.isEmpty {
                let senderKeyResp = try await KeyAPI.getPublicKeys(client: session.client, email: address.email)
                if let pubKey = senderKeyResp.keys.first?.publicKey, !pubKey.isEmpty {
                    let attEncryptor = MessageEncryptor()
                    for att in attachments {
                        let split = try attEncryptor.encryptAttachment(data: att.data, armoredPublicKey: pubKey)
                        let _ = try await MessageAPI.uploadAttachment(
                            client: session.client,
                            messageID: draftID,
                            fileName: att.fileName,
                            mimeType: att.mimeType,
                            keyPackets: split.keyPacket,
                            dataPacket: split.dataPacket
                        )
                    }
                }
            }

            let allRecipients = toAddresses + ccAddresses
            var internalAddrs: [String: SendAddress] = [:]
            var internalBody: String?
            var clearAddrs: [String: SendAddress] = [:]

            let encryptor = MessageEncryptor()
            try encryptor.loadSenderKeys(account.keyPairs)

            for recipient in allRecipients {
                let keyResp = try await KeyAPI.getPublicKeys(client: session.client, email: recipient.address)
                if let pubKey = keyResp.keys.first?.publicKey, !pubKey.isEmpty {
                    let split = try encryptor.encryptForRecipient(
                        plaintext: wrappedBody,
                        recipientArmoredPublicKey: pubKey
                    )
                    internalAddrs[recipient.address] = SendAddress(
                        type: 1,
                        bodyKeyPacket: split.keyPacket.base64EncodedString()
                    )
                    if internalBody == nil {
                        internalBody = split.dataPacket.base64EncodedString()
                    }
                } else {
                    clearAddrs[recipient.address] = SendAddress(type: 4, bodyKeyPacket: "")
                }
            }

            var packages: [SendPackage] = []
            if !internalAddrs.isEmpty, let body = internalBody {
                packages.append(SendPackage(
                    addresses: internalAddrs,
                    mimeType: "text/html",
                    body: body,
                    type: 1
                ))
            }
            if !clearAddrs.isEmpty {
                let signedBody = try session.decryptor.sign(data: Data(wrappedBody.utf8))
                let clearEncrypted = try ClearBodyEncryptor.encryptSignedContent(signedBody)
                packages.append(SendPackage(
                    addresses: clearAddrs,
                    mimeType: "text/html",
                    body: clearEncrypted.dataPacket.base64EncodedString(),
                    type: 4,
                    bodyKey: SessionKey(
                        key: clearEncrypted.sessionKey.base64EncodedString(),
                        algorithm: clearEncrypted.algorithm
                    )
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

    private func encryptBody(session: SessionManager, address: ProtonAddress) async throws -> (encryptedBody: String, wrappedBody: String) {
        let htmlBody = bodyText
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\n", with: "<br>")
        let wrappedBody = "<html><body>\(htmlBody)</body></html>"

        let senderKeyResp = try await KeyAPI.getPublicKeys(client: session.client, email: address.email)
        guard let senderPubKey = senderKeyResp.keys.first?.publicKey, !senderPubKey.isEmpty else {
            throw EncryptionError.encryptionFailed("Failed to get sender public key")
        }
        let encrypted = try MessageDecryptor.encryptWithPublicKey(
            plaintext: wrappedBody,
            armoredPublicKey: senderPubKey
        )
        return (encrypted, wrappedBody)
    }

    private func replyParams() -> (parentID: String?, action: Int?) {
        switch mode {
        case .reply(let msg) where !msg.labelIDs.contains("8"):
            return (msg.id, 0)
        case .replyAll(let msg) where !msg.labelIDs.contains("8"):
            return (msg.id, 1)
        case .forward(let msg) where !msg.labelIDs.contains("8"):
            return (msg.id, 2)
        default:
            return (nil, nil)
        }
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

    private static func buildForwardBody(_ msg: FullMessage) -> String {
        let date = Date(timeIntervalSince1970: msg.time)
            .formatted(.dateTime.year().month().day().hour().minute())
        var body = "\n\n---------- Forwarded message ----------\n"
        body += "From: \(msg.senderName) <\(msg.senderAddress)>\n"
        body += "Date: \(date)\n"
        body += "Subject: \(msg.subject)\n"
        if !msg.toList.isEmpty {
            body += "To: \(msg.toList.map(\.address).joined(separator: ", "))\n"
        }
        body += "\n"
        return body
    }

    private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        if let bodyStart = text.range(of: "<body>"),
           let bodyEnd = text.range(of: "</body>") {
            text = String(text[bodyStart.upperBound..<bodyEnd.lowerBound])
        }
        text = text.replacingOccurrences(of: "<br>", with: "\n")
        text = text.replacingOccurrences(of: "<br/>", with: "\n")
        text = text.replacingOccurrences(of: "<br />", with: "\n")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        return text
    }
}
