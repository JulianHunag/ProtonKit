import SwiftUI
import ProtonCore

struct FolderItem: Identifiable {
    let id: String
    let name: String
    let icon: String
    var unread: Int = 0
    var total: Int = 0
}

struct AccountSidebarSection: Identifiable {
    let uid: String
    let email: String
    let displayName: String
    var systemFolders: [FolderItem]
    var customFolders: [FolderItem]
    var usedSpace: Int64 = 0
    var maxSpace: Int64 = 0
    var id: String { uid }
}

struct SidebarSelection: Hashable {
    let accountUID: String
    let labelID: String
}

@MainActor
final class SidebarViewModel: ObservableObject {
    @Published var selection: SidebarSelection?
    @Published var sections: [AccountSidebarSection] = []

    private static let defaultFolders: [FolderItem] = [
        FolderItem(id: "0", name: "Inbox", icon: "tray"),
        FolderItem(id: "8", name: "Drafts", icon: "doc"),
        FolderItem(id: "7", name: "Sent", icon: "paperplane"),
        FolderItem(id: "10", name: "Starred", icon: "star"),
        FolderItem(id: "6", name: "Archive", icon: "archivebox"),
        FolderItem(id: "4", name: "Spam", icon: "xmark.bin"),
        FolderItem(id: "3", name: "Trash", icon: "trash"),
        FolderItem(id: "5", name: "All Mail", icon: "tray.2"),
    ]

    func load(accounts: [AccountContext]) async {
        var newSections: [AccountSidebarSection] = []

        for account in accounts {
            var section = AccountSidebarSection(
                uid: account.uid,
                email: account.email,
                displayName: account.displayName,
                systemFolders: Self.defaultFolders,
                customFolders: [],
                usedSpace: account.user?.usedSpace ?? 0,
                maxSpace: account.user?.maxSpace ?? 0
            )

            do {
                let countsResp = try await FolderAPI.messageCounts(client: account.client)
                var countMap: [String: Int] = [:]
                var totalMap: [String: Int] = [:]
                for c in countsResp.counts {
                    countMap[c.labelID] = c.unread
                    totalMap[c.labelID] = c.total
                }
                section.systemFolders = Self.defaultFolders.map { folder in
                    var f = folder
                    f.unread = countMap[folder.id] ?? 0
                    f.total = totalMap[folder.id] ?? 0
                    return f
                }

                let labelsResp = try await FolderAPI.list(client: account.client)
                section.customFolders = labelsResp.labels.map { label in
                    FolderItem(
                        id: label.id,
                        name: label.name,
                        icon: "folder",
                        unread: countMap[label.id] ?? 0
                    )
                }
            } catch {
                ProtonClient.debugLog("SidebarVM: failed to load folders for \(account.email): \(error)")
            }

            newSections.append(section)
        }

        sections = newSections

        if selection == nil, let firstSection = sections.first {
            selection = SidebarSelection(accountUID: firstSection.uid, labelID: "0")
        }
    }

    func decrementUnread(accountUID: String, labelID: String) {
        guard let sIdx = sections.firstIndex(where: { $0.uid == accountUID }) else { return }
        if let fIdx = sections[sIdx].systemFolders.firstIndex(where: { $0.id == labelID }) {
            sections[sIdx].systemFolders[fIdx].unread = max(0, sections[sIdx].systemFolders[fIdx].unread - 1)
        } else if let fIdx = sections[sIdx].customFolders.firstIndex(where: { $0.id == labelID }) {
            sections[sIdx].customFolders[fIdx].unread = max(0, sections[sIdx].customFolders[fIdx].unread - 1)
        }
    }

    func incrementUnread(accountUID: String, labelID: String) {
        guard let sIdx = sections.firstIndex(where: { $0.uid == accountUID }) else { return }
        if let fIdx = sections[sIdx].systemFolders.firstIndex(where: { $0.id == labelID }) {
            sections[sIdx].systemFolders[fIdx].unread += 1
        } else if let fIdx = sections[sIdx].customFolders.firstIndex(where: { $0.id == labelID }) {
            sections[sIdx].customFolders[fIdx].unread += 1
        }
    }

    var totalInboxUnread: Int {
        sections.reduce(0) { sum, section in
            sum + (section.systemFolders.first { $0.id == "0" }?.unread ?? 0)
        }
    }

    func refreshCounts(for account: AccountContext) async {
        guard let sIdx = sections.firstIndex(where: { $0.uid == account.uid }) else { return }
        do {
            let countsResp = try await FolderAPI.messageCounts(client: account.client)
            var countMap: [String: Int] = [:]
            var totalMap: [String: Int] = [:]
            for c in countsResp.counts {
                countMap[c.labelID] = c.unread
                totalMap[c.labelID] = c.total
            }
            for i in sections[sIdx].systemFolders.indices {
                let id = sections[sIdx].systemFolders[i].id
                sections[sIdx].systemFolders[i].unread = countMap[id] ?? 0
                sections[sIdx].systemFolders[i].total = totalMap[id] ?? 0
            }
            for i in sections[sIdx].customFolders.indices {
                let id = sections[sIdx].customFolders[i].id
                sections[sIdx].customFolders[i].unread = countMap[id] ?? 0
            }
        } catch {
            ProtonClient.debugLog("SidebarVM: failed to refresh counts: \(error)")
        }
    }
}
