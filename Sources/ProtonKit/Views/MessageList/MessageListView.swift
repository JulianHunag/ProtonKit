import SwiftUI
import AppKit
import ProtonCore

struct MessageListView: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var viewModel: MessageListViewModel
    @Binding var selectedMessageIDs: Set<String>
    var onTrash: ((String) -> Void)?
    var onTrashSelected: (() -> Void)?
    var onToggleUnread: ((String) -> Void)?
    var onToggleUnreadSelected: (() -> Void)?
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
                            onToggleUnreadSelected: { onToggleUnreadSelected?() },
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
                .background {
                    TableViewDoubleClickHelper(
                        messageIDs: viewModel.messages.map(\.id),
                        onDoubleClick: { id in openWindow(id: "message-detail", value: id) }
                    )
                }
            }
        }
        .navigationTitle(viewModel.folderName)
    }
}

struct TableViewDoubleClickHelper: NSViewRepresentable {
    let messageIDs: [String]
    let onDoubleClick: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(messageIDs: messageIDs, onDoubleClick: onDoubleClick)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.frame = .zero
        DispatchQueue.main.async {
            guard let tableView = Self.findTableView(from: view) else { return }
            tableView.target = context.coordinator
            tableView.doubleAction = #selector(Coordinator.handleDoubleClick(_:))
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.messageIDs = messageIDs
        context.coordinator.onDoubleClick = onDoubleClick
    }

    private static func findTableView(from view: NSView) -> NSTableView? {
        var current: NSView? = view
        while let v = current {
            if let found = searchSubtree(v) { return found }
            current = v.superview
        }
        return nil
    }

    private static func searchSubtree(_ view: NSView) -> NSTableView? {
        if let tv = view as? NSTableView { return tv }
        for sub in view.subviews {
            if let found = searchSubtree(sub) { return found }
        }
        return nil
    }

    class Coordinator: NSObject {
        var messageIDs: [String]
        var onDoubleClick: (String) -> Void

        init(messageIDs: [String], onDoubleClick: @escaping (String) -> Void) {
            self.messageIDs = messageIDs
            self.onDoubleClick = onDoubleClick
        }

        @MainActor @objc func handleDoubleClick(_ sender: Any?) {
            guard let tableView = sender as? NSTableView else { return }
            let row = tableView.clickedRow
            guard row >= 0, row < messageIDs.count else { return }
            onDoubleClick(messageIDs[row])
        }
    }
}
