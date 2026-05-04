import SwiftUI
import ProtonCore

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    var onAddAccount: () -> Void

    var body: some View {
        List(selection: $viewModel.selection) {
            ForEach(viewModel.sections) { section in
                Section {
                    ForEach(section.systemFolders) { folder in
                        Label {
                            HStack {
                                Text(folder.name)
                                if folder.id == "0" && folder.total > 0 {
                                    Text("(\(folder.total))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if folder.unread > 0 {
                                    Text("\(folder.unread)")
                                        .font(.caption2.bold())
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.purple.opacity(0.15))
                                        .foregroundStyle(.purple)
                                        .clipShape(Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: folder.icon)
                        }
                        .tag(SidebarSelection(accountUID: section.uid, labelID: folder.id))
                    }

                    if !section.customFolders.isEmpty {
                        ForEach(section.customFolders) { folder in
                            Label(folder.name, systemImage: "folder")
                                .badge(folder.unread)
                                .tag(SidebarSelection(accountUID: section.uid, labelID: folder.id))
                        }
                    }
                } header: {
                    AccountSectionHeader(section: section, isSingleAccount: viewModel.sections.count == 1)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(action: onAddAccount) {
                Label("Add Account", systemImage: "plus")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct AccountSectionHeader: View {
    let section: AccountSidebarSection
    let isSingleAccount: Bool

    var body: some View {
        if isSingleAccount {
            Text("Mailbox")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.displayName)
                    .font(.caption.bold())
                Text(section.email)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
