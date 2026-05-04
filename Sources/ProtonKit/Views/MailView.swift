import SwiftUI
import ProtonCore

struct MailView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var notificationService: NotificationService
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var messageListVM = MessageListViewModel()
    @State private var selectedMessageID: String?
    @State private var searchText = ""
    @State private var composeMode: ComposeMode?

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarVM, onAddAccount: {
                session.isAddingAccount = true
            })
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            MessageListView(
                viewModel: messageListVM,
                selectedMessageID: $selectedMessageID,
                onTrash: { id in Task { await trashMessage(id: id) } },
                onToggleUnread: { id in Task { await toggleUnread(id: id) } }
            )
            .navigationSplitViewColumnWidth(min: 280, ideal: 350, max: 500)
        } detail: {
            if let id = selectedMessageID {
                MessageDetailView(messageID: id)
                    .id(id)
            } else {
                ContentUnavailableView(
                    "No Message Selected",
                    systemImage: "envelope",
                    description: Text("Select a message to read it")
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(action: { composeMode = .newMessage }) {
                    Image(systemName: "square.and.pencil")
                }
                .help("New Message")

                Button(action: { Task { await refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                Button(action: {
                    guard let id = selectedMessageID else { return }
                    Task { await toggleUnread(id: id) }
                }) {
                    Image(systemName: "envelope.badge")
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(selectedMessageID == nil)
                .help("Toggle Read/Unread")

                Button(role: .destructive, action: {
                    guard let id = selectedMessageID else { return }
                    Task { await trashMessage(id: id) }
                }) {
                    Image(systemName: "trash")
                }
                .keyboardShortcut(.delete, modifiers: [])
                .disabled(selectedMessageID == nil)
                .help("Move to Trash")

                accountMenu
            }
        }
        .searchable(text: $searchText, prompt: "Search messages")
        .onSubmit(of: .search) {
            guard let sel = sidebarVM.selection, !searchText.isEmpty else { return }
            Task {
                await messageListVM.search(
                    client: session.client, keyword: searchText, labelID: sel.labelID
                )
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty, let sel = sidebarVM.selection {
                Task { await messageListVM.load(client: session.client, labelID: sel.labelID) }
            }
        }
        .task {
            await loadSidebar()
            if let nav = notificationService.pendingNavigation {
                session.accountStore.setActive(uid: nav.accountUID)
                sidebarVM.selection = SidebarSelection(accountUID: nav.accountUID, labelID: "0")
                notificationService.pendingNavigation = nil
                await messageListVM.load(client: session.client, labelID: "0")
                selectedMessageID = nav.messageID
            }
        }
        .onChange(of: selectedMessageID) { _, newID in
            guard let newID else { return }
            guard let msg = messageListVM.messages.first(where: { $0.id == newID }),
                  msg.unread == 1,
                  let sel = sidebarVM.selection else { return }
            messageListVM.markAsRead(id: newID)
            for labelID in msg.labelIDs {
                sidebarVM.decrementUnread(accountUID: sel.accountUID, labelID: labelID)
            }
            updateDockBadge()
        }
        .onChange(of: sidebarVM.selection) { _, newValue in
            guard let sel = newValue else { return }

            if sel.accountUID != session.accountStore.activeAccountUID {
                session.accountStore.setActive(uid: sel.accountUID)
            }

            selectedMessageID = nil
            Task {
                await messageListVM.load(client: session.client, labelID: sel.labelID)
                if let account = session.accountStore.activeAccount {
                    await sidebarVM.refreshCounts(for: account)
                    updateDockBadge()
                }
            }
        }
        .onChange(of: session.accountStore.accounts.count) { _, _ in
            Task { await loadSidebar() }
        }
        .onChange(of: notificationService.newMailDetected) { _, _ in
            Task { await refresh() }
        }
        .onChange(of: notificationService.pendingNavigation) { _, nav in
            guard let nav else { return }
            session.accountStore.setActive(uid: nav.accountUID)
            sidebarVM.selection = SidebarSelection(accountUID: nav.accountUID, labelID: "0")
            notificationService.pendingNavigation = nil
            Task {
                await sidebarVM.load(accounts: session.accountStore.accounts)
                await messageListVM.load(client: session.client, labelID: "0")
                selectedMessageID = nav.messageID
            }
        }
        .sheet(item: $composeMode) { mode in
            ComposeView(vm: ComposeViewModel(mode: mode))
                .environmentObject(session)
        }
    }

    private var accountMenu: some View {
        Menu {
            ForEach(session.accountStore.accounts) { account in
                Button(action: {
                    session.accountStore.setActive(uid: account.uid)
                    sidebarVM.selection = SidebarSelection(accountUID: account.uid, labelID: "0")
                }) {
                    HStack {
                        Text(account.email)
                        if account.uid == session.accountStore.activeAccountUID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }

            Divider()

            Button("Add Account...") {
                session.isAddingAccount = true
            }

            Divider()

            if let active = session.accountStore.activeAccount {
                Button("Sign Out \(active.email)") {
                    Task { await session.logout() }
                }
            }

            if session.accountStore.accounts.count > 1 {
                Button("Sign Out All") {
                    Task { await session.logoutAll() }
                }
            }
        } label: {
            Image(systemName: "person.circle")
        }
    }

    private func loadSidebar() async {
        await sidebarVM.load(accounts: session.accountStore.accounts)
        if let sel = sidebarVM.selection {
            await messageListVM.load(client: session.client, labelID: sel.labelID)
        }
    }

    private func refresh() async {
        await sidebarVM.load(accounts: session.accountStore.accounts)
        if let sel = sidebarVM.selection {
            await messageListVM.load(client: session.client, labelID: sel.labelID)
        }
    }

    private func trashMessage(id: String) async {
        guard let sel = sidebarVM.selection else { return }
        let msg = messageListVM.messages.first { $0.id == id }
        if id == selectedMessageID { selectedMessageID = nil }
        await messageListVM.trashMessages(client: session.client, ids: [id])
        if let msg, msg.unread == 1 {
            for labelID in msg.labelIDs {
                sidebarVM.decrementUnread(accountUID: sel.accountUID, labelID: labelID)
            }
            updateDockBadge()
        }
    }

    private func toggleUnread(id: String) async {
        guard let sel = sidebarVM.selection,
              let msg = messageListVM.messages.first(where: { $0.id == id }) else { return }
        let wasUnread = msg.unread == 1
        await messageListVM.toggleUnread(client: session.client, id: id)
        for labelID in msg.labelIDs {
            if wasUnread {
                sidebarVM.decrementUnread(accountUID: sel.accountUID, labelID: labelID)
            } else {
                sidebarVM.incrementUnread(accountUID: sel.accountUID, labelID: labelID)
            }
        }
        updateDockBadge()
    }

    private func updateDockBadge() {
        NSApplication.shared.dockTile.badgeLabel =
            sidebarVM.totalInboxUnread > 0 ? "\(sidebarVM.totalInboxUnread)" : nil
    }
}
