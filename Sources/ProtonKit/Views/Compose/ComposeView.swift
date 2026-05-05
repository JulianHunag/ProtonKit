import SwiftUI
import AppKit
import ProtonCore

struct ComposeView: View {
    @EnvironmentObject var session: SessionManager
    @StateObject var vm: ComposeViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            headerFields
            Divider()
            TextEditor(text: $vm.bodyText)
                .font(.body)
                .frame(minHeight: 200)

            if !vm.existingAttachments.isEmpty || !vm.attachments.isEmpty {
                attachmentList
            }

            if let error = vm.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
            }

            Divider()
            bottomBar
        }
        .frame(minWidth: 500, minHeight: 400)
        .onChange(of: vm.didSend) { _, sent in
            if sent { dismiss() }
        }
        .onChange(of: vm.didSaveDraft) { _, saved in
            if saved { dismiss() }
        }
    }

    private var attachmentList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Divider()
            ForEach(vm.existingAttachments) { att in
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                    Text(att.fileName)
                        .font(.caption)
                        .lineLimit(1)
                    Text(formatSize(att.size))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
            ForEach(vm.attachments) { att in
                HStack(spacing: 6) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.secondary)
                    Text(att.fileName)
                        .font(.caption)
                        .lineLimit(1)
                    Text(formatSize(att.data.count))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: { vm.removeAttachment(att) }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }

    private var headerFields: some View {
        VStack(spacing: 8) {
            HStack {
                Text("To:")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("Recipients (comma separated)", text: $vm.toText)
                    .textFieldStyle(.plain)
            }
            Divider()
            HStack {
                Text("Cc:")
                    .frame(width: 40, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("Cc (optional)", text: $vm.ccText)
                    .textFieldStyle(.plain)
            }
            Divider()
            HStack {
                Text("Subject:")
                    .frame(width: 56, alignment: .trailing)
                    .foregroundStyle(.secondary)
                TextField("Subject", text: $vm.subject)
                    .textFieldStyle(.plain)
            }
        }
        .padding()
    }

    private var bottomBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button(action: pickAttachments) {
                Image(systemName: "paperclip")
            }
            .help("Attach Files")

            Spacer()

            if vm.isSending || vm.isSavingDraft {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button("Save Draft") {
                Task { await vm.saveDraft(session: session) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(vm.isSending || vm.isSavingDraft)

            Button("Send") {
                Task { await vm.send(session: session) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(vm.isSending || vm.isSavingDraft || vm.toText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }

    private func pickAttachments() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK {
            vm.addAttachments(urls: panel.urls)
        }
    }
}
