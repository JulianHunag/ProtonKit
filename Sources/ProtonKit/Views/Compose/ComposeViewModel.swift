import SwiftUI
import ProtonCore

enum ComposeMode: Identifiable {
    case reply(FullMessage)
    case replyAll(FullMessage)
    case forward(FullMessage, decryptedHTML: String)
    case newMessage
    case editDraft(FullMessage, decryptedHTML: String)

    var id: String {
        switch self {
        case .reply(let msg): return "reply-\(msg.id)"
        case .replyAll(let msg): return "replyAll-\(msg.id)"
        case .forward(let msg, _): return "forward-\(msg.id)"
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
    private let forwardedHTML: String?

    init(mode: ComposeMode) {
        self.mode = mode
        switch mode {
        case .reply(let msg):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.forwardedHTML = nil
            self.toText = msg.senderAddress
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .replyAll(let msg):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.forwardedHTML = nil
            self.toText = msg.senderAddress
            self.ccText = msg.ccList.map(\.address).joined(separator: ", ")
            self.subject = msg.subject.hasPrefix("Re: ") ? msg.subject : "Re: \(msg.subject)"
            self.bodyText = Self.buildQuotedBody(msg)
        case .forward(let msg, let decryptedHTML):
            self.originalMessage = msg
            self.existingDraftID = nil
            self.forwardedHTML = decryptedHTML
            self.subject = msg.subject.hasPrefix("Fwd: ") ? msg.subject : "Fwd: \(msg.subject)"
            self.bodyText = Self.buildForwardHeader(msg)
        case .newMessage:
            self.originalMessage = nil
            self.existingDraftID = nil
            self.forwardedHTML = nil
        case .editDraft(let msg, let decryptedHTML):
            self.originalMessage = msg
            self.existingDraftID = msg.id
            self.forwardedHTML = nil
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

            let draftID: String
            if let existing = existingDraftID {
                let resp = try await MessageAPI.updateDraft(
                    client: session.client,
                    messageID: existing,
                    subject: subject,
                    body: encryptedBody,
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
                    body: encryptedBody,
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
                if let senderPubKey = senderKeyResp.keys.first?.publicKey, !senderPubKey.isEmpty {
                    for att in attachments {
                        let encrypted = try AttachmentCrypto.encrypt(data: att.data)
                        let keyPacket = try AttachmentCrypto.buildKeyPacket(
                            sessionKey: encrypted.sessionKey,
                            armoredPublicKey: senderPubKey
                        )
                        let _ = try await MessageAPI.uploadAttachment(
                            client: session.client,
                            messageID: draftID,
                            fileName: att.fileName,
                            mimeType: att.mimeType,
                            keyPackets: keyPacket,
                            dataPacket: encrypted.dataPacket
                        )
                    }
                }
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

            // Encrypt and upload attachments, collecting (attachmentID, sessionKey) pairs
            var uploadedAttachments: [(id: String, sessionKey: Data)] = []
            if !attachments.isEmpty {
                let senderKeyResp = try await KeyAPI.getPublicKeys(client: session.client, email: address.email)
                guard let senderPubKey = senderKeyResp.keys.first?.publicKey, !senderPubKey.isEmpty else {
                    throw EncryptionError.encryptionFailed("No sender public key for attachment encryption")
                }
                for att in attachments {
                    let encrypted = try AttachmentCrypto.encrypt(data: att.data)
                    let keyPacket = try AttachmentCrypto.buildKeyPacket(
                        sessionKey: encrypted.sessionKey,
                        armoredPublicKey: senderPubKey
                    )
                    let resp = try await MessageAPI.uploadAttachment(
                        client: session.client,
                        messageID: draftID,
                        fileName: att.fileName,
                        mimeType: att.mimeType,
                        keyPackets: keyPacket,
                        dataPacket: encrypted.dataPacket
                    )
                    uploadedAttachments.append((id: resp.attachment.id, sessionKey: encrypted.sessionKey))
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
                    // Build per-recipient attachment key packets
                    var attKeyPackets: [String: String]?
                    if !uploadedAttachments.isEmpty {
                        var dict: [String: String] = [:]
                        for uploaded in uploadedAttachments {
                            let recipientKeyPacket = try AttachmentCrypto.buildKeyPacket(
                                sessionKey: uploaded.sessionKey,
                                armoredPublicKey: pubKey
                            )
                            dict[uploaded.id] = recipientKeyPacket.base64EncodedString()
                        }
                        attKeyPackets = dict
                    }
                    internalAddrs[recipient.address] = SendAddress(
                        type: 1,
                        bodyKeyPacket: split.keyPacket.base64EncodedString(),
                        attachmentKeyPackets: attKeyPackets
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
                // For cleartext recipients, provide raw session keys for attachments
                var attKeys: [String: SessionKey]?
                if !uploadedAttachments.isEmpty {
                    var dict: [String: SessionKey] = [:]
                    for uploaded in uploadedAttachments {
                        dict[uploaded.id] = SessionKey(
                            key: uploaded.sessionKey.base64EncodedString(),
                            algorithm: "aes256"
                        )
                    }
                    attKeys = dict
                }
                packages.append(SendPackage(
                    addresses: clearAddrs,
                    mimeType: "text/html",
                    body: clearEncrypted.dataPacket.base64EncodedString(),
                    type: 4,
                    bodyKey: SessionKey(
                        key: clearEncrypted.sessionKey.base64EncodedString(),
                        algorithm: clearEncrypted.algorithm
                    ),
                    attachmentKeys: attKeys
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

        let wrappedBody: String
        if let fwdHTML = forwardedHTML {
            let originalBody = Self.extractBodyContent(fwdHTML)
            wrappedBody = "<html><body>\(htmlBody)<br><div>\(originalBody)</div></body></html>"
        } else {
            wrappedBody = "<html><body>\(htmlBody)</body></html>"
        }

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
        case .forward(let msg, _) where !msg.labelIDs.contains("8"):
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

    private static func buildForwardHeader(_ msg: FullMessage) -> String {
        let date = Date(timeIntervalSince1970: msg.time)
            .formatted(.dateTime.year().month().day().hour().minute())
        var header = "\n\n---------- Forwarded message ----------\n"
        header += "From: \(msg.senderName) <\(msg.senderAddress)>\n"
        header += "Date: \(date)\n"
        header += "Subject: \(msg.subject)\n"
        if !msg.toList.isEmpty {
            header += "To: \(msg.toList.map(\.address).joined(separator: ", "))\n"
        }
        return header
    }

    private static func extractBodyContent(_ html: String) -> String {
        if let bodyStart = html.range(of: "<body", options: .caseInsensitive),
           let bodyTagEnd = html[bodyStart.upperBound...].range(of: ">"),
           let bodyEnd = html.range(of: "</body>", options: .caseInsensitive) {
            return String(html[bodyTagEnd.upperBound..<bodyEnd.lowerBound])
        }
        return html
    }

    private static func htmlToPlainText(_ html: String) -> String {
        var text = html
        if let bodyStart = text.range(of: "<body", options: .caseInsensitive),
           let bodyTagEnd = text[bodyStart.upperBound...].range(of: ">"),
           let bodyEnd = text.range(of: "</body>", options: .caseInsensitive) {
            text = String(text[bodyTagEnd.upperBound..<bodyEnd.lowerBound])
        }
        while let s = text.range(of: "<style", options: .caseInsensitive),
              let e = text.range(of: "</style>", options: .caseInsensitive, range: s.lowerBound..<text.endIndex) {
            text.removeSubrange(s.lowerBound..<e.upperBound)
        }
        while let s = text.range(of: "<script", options: .caseInsensitive),
              let e = text.range(of: "</script>", options: .caseInsensitive, range: s.lowerBound..<text.endIndex) {
            text.removeSubrange(s.lowerBound..<e.upperBound)
        }
        for tag in ["<br>", "<br/>", "<br />"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        for tag in ["</p>", "</div>", "</tr>", "</li>", "</h1>", "</h2>", "</h3>", "</td>"] {
            text = text.replacingOccurrences(of: tag, with: "\n", options: .caseInsensitive)
        }
        while let tagStart = text.range(of: "<"),
              let tagEnd = text.range(of: ">", range: tagStart.lowerBound..<text.endIndex) {
            text.removeSubrange(tagStart.lowerBound...tagEnd.lowerBound)
        }
        text = text.replacingOccurrences(of: "&nbsp;", with: " ")
        text = text.replacingOccurrences(of: "&lt;", with: "<")
        text = text.replacingOccurrences(of: "&gt;", with: ">")
        text = text.replacingOccurrences(of: "&amp;", with: "&")
        text = text.replacingOccurrences(of: "&quot;", with: "\"")
        text = text.replacingOccurrences(of: "&#39;", with: "'")
        while text.contains("\n\n\n") {
            text = text.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
