import SwiftUI
import ProtonCore

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            let minimized = sender.windows.filter { $0.isMiniaturized }
            if !minimized.isEmpty {
                for window in minimized {
                    window.deminiaturize(nil)
                    window.makeKeyAndOrderFront(nil)
                }
                return false
            }
        }
        return true
    }
}

@main
struct ProtonKitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var session = SessionManager()
    @StateObject private var notificationService = NotificationService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(session)
                .environmentObject(notificationService)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    _ = await session.restoreSession()
                    if !notificationService.isConfigured {
                        notificationService.configure(accountStore: session.accountStore)
                        if await notificationService.requestPermission() {
                            notificationService.startPolling()
                        }
                    }
                }
                .onAppear {
                    enforceOneWindow()
                }
        }
        .defaultSize(width: 1200, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }

    private func enforceOneWindow() {
        let appWindows = NSApplication.shared.windows.filter {
            ($0.isVisible || $0.isMiniaturized) && $0.className == "SwiftUI.SwiftUIWindow"
        }
        guard appWindows.count > 1, let oldest = appWindows.first else { return }

        if oldest.isMiniaturized {
            oldest.deminiaturize(nil)
        }
        oldest.makeKeyAndOrderFront(nil)

        for window in appWindows.dropFirst() {
            window.close()
        }
    }
}
