import SwiftUI
import ProtonCore

@MainActor
final class MessageListViewModel: ObservableObject {
    @Published var messages: [MessageMetadata] = []
    @Published var isLoading = false
    @Published var hasMore = false
    @Published var folderName = "Inbox"

    private var client: ProtonClient?
    private var currentLabelID = "0"
    private var currentPage = 0
    private var total = 0
    private let pageSize = 50
    private var currentKeyword: String?

    func load(client: ProtonClient, labelID: String) async {
        self.client = client
        self.currentLabelID = labelID
        self.currentPage = 0
        self.currentKeyword = nil
        self.folderName = SystemLabel(rawValue: labelID)?.displayName ?? "Folder"

        isLoading = true
        do {
            let resp = try await MessageAPI.list(
                client: client,
                labelID: labelID,
                page: 0,
                pageSize: pageSize
            )
            messages = resp.messages
            total = resp.total
            hasMore = messages.count < total
        } catch {
            print("Failed to load messages: \(error)")
        }
        isLoading = false
    }

    func markAsRead(id: String) {
        if let idx = messages.firstIndex(where: { $0.id == id }) {
            messages[idx].unread = 0
        }
    }

    func trashMessages(client: ProtonClient, ids: [String]) async {
        try? await MessageAPI.trash(client: client, messageIDs: ids)
        messages.removeAll { ids.contains($0.id) }
    }

    func toggleUnread(client: ProtonClient, id: String) async {
        guard let idx = messages.firstIndex(where: { $0.id == id }) else { return }
        if messages[idx].unread == 1 {
            try? await MessageAPI.markRead(client: client, messageIDs: [id])
            messages[idx].unread = 0
        } else {
            try? await MessageAPI.markUnread(client: client, messageIDs: [id])
            messages[idx].unread = 1
        }
    }

    func markUnread(client: ProtonClient, ids: [String]) async {
        try? await MessageAPI.markUnread(client: client, messageIDs: ids)
        for id in ids {
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].unread = 1
            }
        }
    }

    func markRead(client: ProtonClient, ids: [String]) async {
        try? await MessageAPI.markRead(client: client, messageIDs: ids)
        for id in ids {
            if let idx = messages.firstIndex(where: { $0.id == id }) {
                messages[idx].unread = 0
            }
        }
    }

    func loadMore() async {
        guard let client, hasMore, !isLoading else { return }
        currentPage += 1
        isLoading = true

        do {
            let resp = try await MessageAPI.list(
                client: client,
                labelID: currentLabelID,
                page: currentPage,
                pageSize: pageSize,
                keyword: currentKeyword
            )
            messages.append(contentsOf: resp.messages)
            hasMore = messages.count < total
        } catch {
            print("Failed to load more: \(error)")
        }
        isLoading = false
    }

    func search(client: ProtonClient, keyword: String, labelID: String) async {
        self.client = client
        self.currentLabelID = labelID
        self.currentPage = 0
        self.currentKeyword = keyword
        self.folderName = "Search: \(keyword)"

        isLoading = true
        do {
            let resp = try await MessageAPI.list(
                client: client,
                labelID: labelID,
                page: 0,
                pageSize: pageSize,
                keyword: keyword
            )
            messages = resp.messages
            total = resp.total
            hasMore = messages.count < total
        } catch {
            print("Failed to search: \(error)")
        }
        isLoading = false
    }
}
