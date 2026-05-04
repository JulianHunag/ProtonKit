import SwiftUI
import WebKit
import ProtonCore

struct MessageDetailView: View {
    let messageID: String
    @EnvironmentObject var session: SessionManager
    @StateObject private var vm = MessageDetailViewModel()
    @State private var webViewHeight: CGFloat = 400

    var body: some View {
        Group {
            if vm.isLoading {
                ProgressView("Decrypting message...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let msg = vm.message {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        messageHeader(msg)
                        Divider()
                        HTMLWebView(html: vm.bodyHTML, contentHeight: $webViewHeight)
                            .frame(height: max(webViewHeight, 100))

                        if !msg.attachments.isEmpty {
                            attachmentSection(msg.attachments)
                        }
                    }
                    .padding()
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
                HStack {
                    Image(systemName: "doc")
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
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
