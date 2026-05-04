import Foundation
import Combine

@MainActor
public final class SessionManager: ObservableObject {
    @Published public var accountStore = AccountStore()
    @Published public var needsTwoFactor = false
    @Published public var isAddingAccount = false
    @Published public var isRestoring = true

    public var pendingContext: AccountContext?
    private var pendingPassword: String?
    private var cancellable: AnyCancellable?

    public init() {
        cancellable = accountStore.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    // MARK: - Computed Properties (backward compat)

    public var isLoggedIn: Bool { !accountStore.accounts.isEmpty }

    public var client: ProtonClient {
        accountStore.activeAccount?.client ?? _fallbackClient
    }

    public var decryptor: MessageDecryptor {
        accountStore.activeAccount?.decryptor ?? _fallbackDecryptor
    }

    public var currentUser: ProtonUser? {
        accountStore.activeAccount?.user
    }

    public var addresses: [ProtonAddress] {
        accountStore.activeAccount?.addresses ?? []
    }

    private let _fallbackClient = ProtonClient()
    private let _fallbackDecryptor = MessageDecryptor()

    // MARK: - Login

    public func login(username: String, password: String) async throws {
        let (ctx, needs2FA) = try await accountStore.loginNewAccount(username: username, password: password)

        if needs2FA {
            pendingContext = ctx
            pendingPassword = password
            needsTwoFactor = true
            return
        }

        try await accountStore.completeLogin(context: ctx, password: password)
        pendingContext = nil
        pendingPassword = nil
    }

    public func submit2FA(code: String, password: String) async throws {
        guard let ctx = pendingContext else { return }
        try await accountStore.submit2FA(context: ctx, code: code)
        try await accountStore.completeLogin(context: ctx, password: password)
        needsTwoFactor = false
        pendingContext = nil
        pendingPassword = nil
    }

    public func cancelTwoFactor() {
        needsTwoFactor = false
        pendingContext = nil
        pendingPassword = nil
    }

    // MARK: - Session Restore

    public func restoreSession() async -> Bool {
        guard accountStore.accounts.isEmpty else {
            isRestoring = false
            return true
        }
        isRestoring = true
        await accountStore.restoreAllAccounts()
        isRestoring = false
        return !accountStore.accounts.isEmpty
    }

    // MARK: - Logout

    public func logout() async {
        guard let uid = accountStore.activeAccountUID else { return }
        await accountStore.logoutAccount(uid: uid)
    }

    public func logoutAll() async {
        await accountStore.logoutAll()
    }
}
