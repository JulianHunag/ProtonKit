import SwiftUI
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

            Spacer()

            if vm.isSending {
                ProgressView()
                    .controlSize(.small)
                    .padding(.trailing, 4)
            }

            Button("Send") {
                Task { await vm.send(session: session) }
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(vm.isSending || vm.toText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
    }
}
