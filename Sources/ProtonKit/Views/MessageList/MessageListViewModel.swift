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

    func load(client: ProtonClient, labelID: String) async {
        self.client = client
        self.currentLabelID = labelID
        self.currentPage = 0
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

    func loadMore() async {
        guard let client, hasMore, !isLoading else { return }
        currentPage += 1
        isLoading = true

        do {
            let resp = try await MessageAPI.list(
                client: client,
                labelID: currentLabelID,
                page: currentPage,
                pageSize: pageSize
            )
            messages.append(contentsOf: resp.messages)
            hasMore = messages.count < total
        } catch {
            print("Failed to load more: \(error)")
        }
        isLoading = false
    }
}
