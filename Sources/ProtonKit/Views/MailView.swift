import SwiftUI
import ProtonCore

struct MailView: View {
    @EnvironmentObject var session: SessionManager
    @EnvironmentObject var notificationService: NotificationService
    @StateObject private var sidebarVM = SidebarViewModel()
    @StateObject private var messageListVM = MessageListViewModel()
    @State private var selectedMessageID: String?

    var body: some View {
        NavigationSplitView {
            SidebarView(viewModel: sidebarVM, onAddAccount: {
                session.isAddingAccount = true
            })
            .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)
        } content: {
            MessageListView(
                viewModel: messageListVM,
                selectedMessageID: $selectedMessageID
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
                Button(action: { Task { await refresh() } }) {
                    Image(systemName: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)

                accountMenu
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
            NSApplication.shared.dockTile.badgeLabel =
                sidebarVM.totalInboxUnread > 0 ? "\(sidebarVM.totalInboxUnread)" : nil
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
                    NSApplication.shared.dockTile.badgeLabel =
                        sidebarVM.totalInboxUnread > 0 ? "\(sidebarVM.totalInboxUnread)" : nil
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
}
