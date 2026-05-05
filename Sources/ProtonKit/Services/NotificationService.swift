import Foundation
import UserNotifications
import AppKit
import ProtonCore

struct NotificationNavigation: Equatable {
    let accountUID: String
    let messageID: String
}

@MainActor
final class NotificationService: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    private var timer: Timer?
    private weak var accountStore: AccountStore?

    var pollInterval: TimeInterval = 30

    private var lastEventIDs: [String: String] = [:]
    private let lastEventKey = "protonkit.lastEventIDs"

    @Published var pendingNavigation: NotificationNavigation?
    @Published var newMailDetected: Int = 0
    private(set) var isConfigured = false

    override init() {
        super.init()
        loadLastEventIDs()
        UNUserNotificationCenter.current().delegate = self
    }

    func configure(accountStore: AccountStore) {
        self.accountStore = accountStore
        isConfigured = true
    }

    func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            return granted
        } catch {
            ProtonClient.debugLog("NotificationService: permission request failed: \(error)")
            return false
        }
    }

    func startPolling() {
        stopPolling()
        ProtonClient.debugLog("NotificationService: starting event poll every \(Int(pollInterval))s")

        Task { await initializeEventIDs() }

        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                await self.pollAllAccounts()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Event Polling

    private func initializeEventIDs() async {
        guard let accounts = accountStore?.accounts else { return }
        for account in accounts {
            if lastEventIDs[account.uid] == nil {
                do {
                    let eventID = try await EventAPI.getLatestEventID(client: account.client)
                    lastEventIDs[account.uid] = eventID
                } catch {
                    ProtonClient.debugLog("NotificationService: failed to get latest event for \(account.email): \(error)")
                }
            }
        }
        persistLastEventIDs()
    }

    private func pollAllAccounts() async {
        guard let accounts = accountStore?.accounts else { return }

        var totalUnread = 0
        for account in accounts {
            await pollAccount(account)
            totalUnread += await inboxUnreadCount(account)
        }

        updateDockBadge(totalUnread)
    }

    private func pollAccount(_ context: AccountContext) async {
        guard let eventID = lastEventIDs[context.uid] else {
            do {
                let id = try await EventAPI.getLatestEventID(client: context.client)
                lastEventIDs[context.uid] = id
                persistLastEventIDs()
            } catch {
                ProtonClient.debugLog("NotificationService: init event ID failed for \(context.email): \(error)")
            }
            return
        }

        do {
            var currentEventID = eventID
            var hasMore = true

            while hasMore {
                let resp = try await EventAPI.getEvents(client: context.client, eventID: currentEventID)
                currentEventID = resp.eventID
                hasMore = resp.more == 1

                if let messages = resp.messages {
                    for event in messages {
                        if event.action == MessageEvent.Action.create.rawValue,
                           let msg = event.message, msg.unread == 1,
                           msg.labelIDs.contains("0") {
                            postNotification(account: context, message: msg)
                            newMailDetected += 1
                        }
                    }
                }
            }

            if currentEventID != eventID {
                lastEventIDs[context.uid] = currentEventID
                persistLastEventIDs()
            }
        } catch {
            ProtonClient.debugLog("NotificationService: event poll failed for \(context.email): \(error)")
        }
    }

    private func inboxUnreadCount(_ context: AccountContext) async -> Int {
        do {
            let resp = try await FolderAPI.messageCounts(client: context.client)
            return resp.counts.first { $0.labelID == "0" }?.unread ?? 0
        } catch {
            return 0
        }
    }

    // MARK: - Notification

    private func postNotification(account: AccountContext, message: MessageMetadata) {
        let content = UNMutableNotificationContent()
        content.title = message.senderName
        content.subtitle = message.subject
        content.sound = .default
        content.threadIdentifier = account.uid
        content.userInfo = [
            "accountUID": account.uid,
            "messageID": message.id,
        ]

        let identifier = "\(account.uid)-\(message.id)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                ProtonClient.debugLog("NotificationService: failed to post notification: \(error)")
            }
        }
    }

    private func updateDockBadge(_ count: Int) {
        NSApplication.shared.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let uid = userInfo["accountUID"] as? String,
              let messageID = userInfo["messageID"] as? String else { return }

        await MainActor.run {
            NSApplication.shared.activate(ignoringOtherApps: true)
            for window in NSApplication.shared.windows where window.isMiniaturized {
                window.deminiaturize(nil)
            }
            pendingNavigation = NotificationNavigation(accountUID: uid, messageID: messageID)
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    // MARK: - Persistence

    private func loadLastEventIDs() {
        if let data = UserDefaults.standard.data(forKey: lastEventKey),
           let dict = try? JSONDecoder().decode([String: String].self, from: data) {
            lastEventIDs = dict
        }
    }

    private func persistLastEventIDs() {
        if let data = try? JSONEncoder().encode(lastEventIDs) {
            UserDefaults.standard.set(data, forKey: lastEventKey)
        }
    }
}
