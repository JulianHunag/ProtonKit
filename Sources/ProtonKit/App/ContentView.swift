import SwiftUI
import ProtonCore

struct ContentView: View {
    @EnvironmentObject var session: SessionManager

    var body: some View {
        Group {
            let _ = ProtonClient.debugLog("ContentView: isRestoring=\(session.isRestoring) isLoggedIn=\(session.isLoggedIn) accounts=\(session.accountStore.accounts.count)")
            if session.isRestoring {
                VStack(spacing: 20) {
                    if let icon = NSImage(named: "AppIcon") {
                        Image(nsImage: icon)
                            .resizable()
                            .frame(width: 96, height: 96)
                            .clipShape(RoundedRectangle(cornerRadius: 20))
                    }
                    ProgressView()
                        .controlSize(.regular)
                    Text("Restoring session...")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            } else if session.isLoggedIn {
                MailView()
                    .sheet(isPresented: $session.isAddingAccount) {
                        LoginView(isAddingAccount: true)
                            .environmentObject(session)
                            .frame(minWidth: 480, minHeight: 420)
                    }
            } else {
                LoginView(isAddingAccount: false)
            }
        }
    }
}
