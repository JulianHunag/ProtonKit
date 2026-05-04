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

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Decrypting message...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.message {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        messageHeader(msg)

                        HStack(spacing: 12) {
                            Button(action: { composeMode = .reply(msg) }) {
                                Label("Reply", systemImage: "arrowshape.turn.up.left")
                            }
                            Button(action: { composeMode = .replyAll(msg) }) {
                                Label("Reply All", systemImage: "arrowshape.turn.up.left.2")
                            }
                            Spacer()
                        }

                        Divider()
                        HTMLWebView(html: vm.bodyHTML, contentHeight: $webViewHeight)
                            .frame(height: max(webViewHeight, 100))

                        if !msg.attachments.isEmpty {
                            attachmentSection(msg.attachments)
                        }
                    }
                    .padding()
                }
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
        .task(id: messageID) {
            await vm.load(client: session.client, messageID: messageID, decryptor: session.decryptor)
        }
    }

    private func messageHeader(_ msg: FullMessage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(msg.subject)
                .font(.title2.bold())

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(msg.senderName.isEmpty ? msg.senderAddress : msg.senderName)
                        .font(.headline)
                    if !msg.senderName.isEmpty {
                        Text(msg.senderAddress)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Text(Date(timeIntervalSince1970: msg.time).formatted(
                    .dateTime.year().month().day().hour().minute()
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if !msg.toList.isEmpty {
                HStack(alignment: .top) {
                    Text("To:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(msg.toList.map { $0.address }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !msg.ccList.isEmpty {
                HStack(alignment: .top) {
                    Text("Cc:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(msg.ccList.map { $0.address }.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func attachmentSection(_ attachments: [FullMessage.Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text("Attachments (\(attachments.count))")
                .font(.headline)

            ForEach(attachments) { att in
                Button(action: { Task { await downloadAttachment(att) } }) {
                    HStack {
                        if downloadingAttachmentID == att.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.down.circle")
                        }
                        Text(att.name)
                            .lineLimit(1)
                        Spacer()
                        Text(formatSize(att.size))
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .padding(8)
                    .background(.quaternary)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(downloadingAttachmentID != nil)
            }
        }
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
