import SwiftUI
import WebKit
import ProtonCore

struct MessageDetailView: View {
    let messageID: String
    @EnvironmentObject var session: SessionManager
    @StateObject private var vm = MessageDetailViewModel()
    @State private var webViewHeight: CGFloat = 400
    @State private var downloadingAttachmentID: String?
    @State private var composeMode: ComposeMode?
    @State private var showAllRecipients = false

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Decrypting message...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.message {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        messageHeader(msg)
                            .padding(.bottom, 4)
                        actionButtons(msg)

                        Divider()
                        HTMLWebView(html: vm.bodyHTML, contentHeight: $webViewHeight)
                            .frame(height: max(webViewHeight, 100))

                        if !msg.attachments.isEmpty {
                            attachmentSection(msg.attachments)
                        }
                    }
                    .padding()
                }
                .transition(.opacity)
                .sheet(item: $composeMode) { mode in
                    ComposeView(vm: ComposeViewModel(mode: mode))
                        .environmentObject(session)
                }
            } else if let error = vm.errorMessage {
                ContentUnavailableView(
                    "Failed to load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else {
                ProgressView("Loading...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: vm.message != nil)
        .task(id: messageID) {
            showAllRecipients = false
            await vm.load(client: session.client, messageID: messageID, decryptor: session.decryptor)
        }
    }

    private func messageHeader(_ msg: FullMessage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(msg.subject)
                .font(.title2.bold())

            HStack(alignment: .top, spacing: 12) {
                AvatarView(
                    name: msg.senderName.isEmpty ? msg.senderAddress : msg.senderName,
                    size: 40
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(msg.senderName.isEmpty ? msg.senderAddress : msg.senderName)
                        .font(.headline)
                    Text(msg.senderAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    recipientsRow(msg)
                }

                Spacer()

                Text(Date(timeIntervalSince1970: msg.time).formatted(
                    .dateTime.year().month().day().hour().minute()
                ))
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
        }
    }

    private func recipientsRow(_ msg: FullMessage) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Button(action: { withAnimation(.snappy(duration: 0.2)) { showAllRecipients.toggle() } }) {
                HStack(spacing: 4) {
                    Text("To: \(recipientSummary(msg.toList))")
                        .lineLimit(1)
                    if msg.toList.count > 1 || !msg.ccList.isEmpty {
                        Image(systemName: showAllRecipients ? "chevron.up" : "chevron.down")
                            .imageScale(.small)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            if showAllRecipients {
                if msg.toList.count > 1 {
                    ForEach(msg.toList.dropFirst(), id: \.address) { addr in
                        Text("    \(addr.name ?? addr.address)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !msg.ccList.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("Cc:")
                            .foregroundStyle(.tertiary)
                        Text(msg.ccList.map { $0.name ?? $0.address }.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func recipientSummary(_ list: [EmailAddress]) -> String {
        guard let first = list.first else { return "" }
        let name = first.name ?? first.address
        if list.count > 1 {
            return "\(name) +\(list.count - 1)"
        }
        return name
    }

    private func actionButtons(_ msg: FullMessage) -> some View {
        HStack(spacing: 6) {
            if msg.labelIDs.contains("8") {
                Button(action: {
                    composeMode = .editDraft(msg, decryptedHTML: vm.rawDecryptedBody)
                }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .help("Edit Draft")
            } else {
                Button(action: { composeMode = .reply(msg) }) {
                    Image(systemName: "arrowshape.turn.up.left")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .help("Reply")

                Button(action: { composeMode = .replyAll(msg) }) {
                    Image(systemName: "arrowshape.turn.up.left.2")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .help("Reply All")

                Button(action: { composeMode = .forward(msg, decryptedHTML: vm.rawDecryptedBody) }) {
                    Image(systemName: "arrowshape.turn.up.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .buttonBorderShape(.capsule)
                .help("Forward")
            }
            Spacer()
        }
    }

    private func attachmentSection(_ attachments: [FullMessage.Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Label("Attachments (\(attachments.count))", systemImage: "paperclip")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(attachments) { att in
                        Button(action: { Task { await downloadAttachment(att) } }) {
                            HStack(spacing: 6) {
                                if downloadingAttachmentID == att.id {
                                    ProgressView()
                                        .controlSize(.mini)
                                } else {
                                    Image(systemName: iconForMIME(att.mimeType))
                                        .foregroundStyle(.blue)
                                }
                                Text(att.name)
                                    .lineLimit(1)
                                    .font(.caption)
                                Text(formatSize(att.size))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.quaternary, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(downloadingAttachmentID != nil)
                    }
                }
            }
        }
    }

    private func iconForMIME(_ mimeType: String) -> String {
        if mimeType.hasPrefix("image/") { return "photo" }
        if mimeType == "application/pdf" { return "doc.richtext" }
        if mimeType.contains("zip") || mimeType.contains("compressed") { return "doc.zipper" }
        if mimeType.contains("spreadsheet") || mimeType.contains("excel") { return "tablecells" }
        if mimeType.contains("presentation") || mimeType.contains("powerpoint") { return "play.rectangle" }
        return "doc"
    }

    private func downloadAttachment(_ att: FullMessage.Attachment) async {
        downloadingAttachmentID = att.id
        defer { downloadingAttachmentID = nil }

        do {
            let encryptedData = try await MessageAPI.downloadAttachment(
                client: session.client, attachmentID: att.id
            )

            let fileData: Data
            if let keyPacketsBase64 = att.keyPackets,
               let keyPackets = Data(base64Encoded: keyPacketsBase64) {
                fileData = try session.decryptor.decryptAttachment(
                    keyPackets: keyPackets, dataPackets: encryptedData
                )
            } else {
                fileData = encryptedData
            }

            let panel = NSSavePanel()
            panel.nameFieldStringValue = att.name
            panel.canCreateDirectories = true
            let response = panel.runModal()
            if response == .OK, let url = panel.url {
                try fileData.write(to: url)
            }
        } catch {
            ProtonClient.debugLog("Attachment download failed: \(error)")
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
