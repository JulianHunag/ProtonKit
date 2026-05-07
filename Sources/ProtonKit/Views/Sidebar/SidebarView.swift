import SwiftUI
import ProtonCore

struct SidebarView: View {
    @ObservedObject var viewModel: SidebarViewModel
    var onAddAccount: () -> Void
    var onCompose: () -> Void

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
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer()
                                if folder.unread > 0 {
                                    Text("\(folder.unread)")
                                        .font(.caption2.weight(.semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(folderColor(folder).opacity(0.15))
                                        .foregroundStyle(folderColor(folder))
                                        .clipShape(Capsule())
                                }
                            }
                        } icon: {
                            Image(systemName: folder.icon)
                                .foregroundStyle(folderColor(folder))
                        }
                        .tag(SidebarSelection(accountUID: section.uid, labelID: folder.id))
                    }

                    if !section.customFolders.isEmpty {
                        ForEach(section.customFolders) { folder in
                            Label(folder.name, systemImage: "folder.fill")
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
        .safeAreaInset(edge: .top) {
            Button(action: onCompose) {
                Label("New Message", systemImage: "square.and.pencil")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onAddAccount) {
                Label("Add Account", systemImage: "plus.circle.fill")
                    .font(.subheadline)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func folderColor(_ folder: FolderItem) -> Color {
        switch folder.iconColor {
        case "blue": return .blue
        case "gray": return .gray
        case "teal": return .teal
        case "yellow": return .yellow
        case "purple": return .purple
        case "orange": return .orange
        case "red": return .red
        default: return .blue
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
        fraction >= 0.9 ? .red : .blue
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(barColor.gradient)
                        .frame(width: geo.size.width * min(fraction, 1.0))
                }
            }
            .frame(height: 5)

            Text("\(formatBytes(usedSpace)) / \(formatBytes(maxSpace))")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
            HStack(spacing: 8) {
                AvatarView(name: section.displayName, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.displayName)
                        .font(.caption.bold())
                    Text(section.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        } else {
            HStack(spacing: 8) {
                AvatarView(name: section.displayName, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(section.displayName)
                        .font(.caption.bold())
                    Text(section.email)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, 2)
        }
    }
}
