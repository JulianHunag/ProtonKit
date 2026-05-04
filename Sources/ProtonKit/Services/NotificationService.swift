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

    var pollInterval: TimeInterval = 300

    private var lastSeenTimestamps: [String: TimeInterval] = [:]
    private let lastSeenKey = "protonkit.notificationLastSeen"

    @Published var pendingNavigation: NotificationNavigation?
    @Published var newMailDetected: Int = 0
    private(set) var isConfigured = false

    override init() {
        super.init()
        loadLastSeen()
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
        ProtonClient.debugLog("NotificationService: starting poll every \(Int(pollInterval))s")

        initializeLastSeen()

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

    // MARK: - Polling

    private func initializeLastSeen() {
        guard let accounts = accountStore?.accounts else { return }
        for account in accounts {
            if lastSeenTimestamps[account.uid] == nil {
                lastSeenTimestamps[account.uid] = Date().timeIntervalSince1970
            }
        }
        persistLastSeen()
    }

    private func pollAllAccounts() async {
        guard let accounts = accountStore?.accounts else { return }

        var totalUnread = 0
        for account in accounts {
            await checkAccount(account)
            totalUnread += await inboxUnreadCount(account)
        }

        updateDockBadge(totalUnread)
    }

    private func checkAccount(_ context: AccountContext) async {
        do {
            let resp = try await MessageAPI.list(
                client: context.client,
                labelID: "0",
                page: 0,
                pageSize: 5
            )

            let lastSeen = lastSeenTimestamps[context.uid] ?? 0

            let newMessages = resp.messages.filter { $0.time > lastSeen && $0.unread == 1 }

            for msg in newMessages {
                postNotification(account: context, message: msg)
            }

            if !newMessages.isEmpty {
                newMailDetected += 1
            }

            if let newest = resp.messages.first, newest.time > lastSeen {
                lastSeenTimestamps[context.uid] = newest.time
                persistLastSeen()
            }
        } catch {
            ProtonClient.debugLog("NotificationService: poll failed for \(context.email): \(error)")
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

    private func loadLastSeen() {
        if let data = UserDefaults.standard.data(forKey: lastSeenKey),
           let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            lastSeenTimestamps = dict
        }
    }

    private func persistLastSeen() {
        if let data = try? JSONEncoder().encode(lastSeenTimestamps) {
            UserDefaults.standard.set(data, forKey: lastSeenKey)
        }
    }
}
