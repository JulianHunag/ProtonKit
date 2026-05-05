import SwiftUI
import ProtonCore

struct MessageListView: View {
    @ObservedObject var viewModel: MessageListViewModel
    @Binding var selectedMessageIDs: Set<String>
    var onTrash: ((String) -> Void)?
    var onTrashSelected: (() -> Void)?
    var onToggleUnread: ((String) -> Void)?
    var onReply: ((String) -> Void)?
    var onReplyAll: ((String) -> Void)?
    var onForward: ((String) -> Void)?

    var body: some View {
        Group {
            if viewModel.isLoading && viewModel.messages.isEmpty {
                ProgressView("Loading messages...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.messages.isEmpty {
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "tray",
                    description: Text("This folder is empty")
                )
            } else {
                List(selection: $selectedMessageIDs) {
                    ForEach(viewModel.messages) { msg in
                        MessageRowView(
                            message: msg,
                            isMultiSelected: selectedMessageIDs.count > 1 && selectedMessageIDs.contains(msg.id),
                            onTrash: { onTrash?(msg.id) },
                            onTrashSelected: { onTrashSelected?() },
                            onToggleUnread: { onToggleUnread?(msg.id) },
                            onReply: { onReply?(msg.id) },
                            onReplyAll: { onReplyAll?(msg.id) },
                            onForward: { onForward?(msg.id) }
                        )
                        .tag(msg.id)
                    }

                    if viewModel.hasMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .task {
                                await viewModel.loadMore()
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
        .navigationTitle(viewModel.folderName)
    }
}
