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

                    if section.maxSpace > 0 {
                        StorageUsageView(usedSpace: section.usedSpace, maxSpace: section.maxSpace)
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

private struct StorageUsageView: View {
    let usedSpace: Int64
    let maxSpace: Int64

    private var fraction: Double {
        guard maxSpace > 0 else { return 0 }
        return Double(usedSpace) / Double(maxSpace)
    }

    private var barColor: Color {
        fraction >= 0.9 ? .red : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * min(fraction, 1.0))
                }
            }
            .frame(height: 4)

            Text("\(formatBytes(usedSpace)) / \(formatBytes(maxSpace))")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.0f MB", mb)
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
