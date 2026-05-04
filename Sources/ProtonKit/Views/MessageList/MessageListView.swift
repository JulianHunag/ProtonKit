import SwiftUI
import ProtonCore

struct MessageListView: View {
    @ObservedObject var viewModel: MessageListViewModel
    @Binding var selectedMessageID: String?
    var onTrash: ((String) -> Void)?
    var onToggleUnread: ((String) -> Void)?

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
                List(selection: $selectedMessageID) {
                    ForEach(viewModel.messages) { msg in
                        MessageRowView(
                            message: msg,
                            onTrash: { onTrash?(msg.id) },
                            onToggleUnread: { onToggleUnread?(msg.id) }
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
