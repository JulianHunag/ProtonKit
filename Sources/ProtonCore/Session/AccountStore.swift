import Foundation

@MainActor
public final class AccountStore: ObservableObject {
    @Published public var accounts: [AccountContext] = []
    @Published public var activeAccountUID: String?

    private let accountListKey = "protonkit.savedAccounts"

    public init() {}

    public var activeAccount: AccountContext? {
        guard let uid = activeAccountUID else { return accounts.first }
        return accounts.first { $0.uid == uid }
    }

    // MARK: - Account Lifecycle

    public func addAccount(_ context: AccountContext) {
        if !accounts.contains(where: { $0.uid == context.uid }) {
            accounts.append(context)
        }
        if activeAccountUID == nil {
            activeAccountUID = context.uid
        }
        persistDescriptors()
    }

    public func removeAccount(uid: String) {
        KeychainStore.deleteAll(namespace: uid)
        accounts.removeAll { $0.uid == uid }
        if activeAccountUID == uid {
            activeAccountUID = accounts.first?.uid
        }
        persistDescriptors()
    }

    public func setActive(uid: String) {
        guard accounts.contains(where: { $0.uid == uid }) else { return }
        activeAccountUID = uid
    }

    // MARK: - Persistence

    public func savedDescriptors() -> [AccountDescriptor] {
        guard let data = UserDefaults.standard.data(forKey: accountListKey),
              let list = try? JSONDecoder().decode([AccountDescriptor].self, from: data) else {
            return []
        }
        return list
    }

    public func persistDescriptors() {
        let list = accounts.map { $0.descriptor }
        if let data = try? JSONEncoder().encode(list) {
            UserDefaults.standard.set(data, forKey: accountListKey)
        }
    }

    // MARK: - Session Restore

    public func restoreAllAccounts() async {
        guard accounts.isEmpty else { return }
        migrateIfNeeded()

        let descriptors = savedDescriptors()
        ProtonClient.debugLog("AccountStore: restoring \(descriptors.count) accounts")

        for desc in descriptors {
            do {
                let ctx = try await restoreAccount(uid: desc.uid)
                accounts.append(ctx)
                ProtonClient.debugLog("AccountStore: restored \(desc.email)")
            } catch {
                ProtonClient.debugLog("AccountStore: failed to restore \(desc.email): \(error)")
            }
        }

        if activeAccountUID == nil {
            activeAccountUID = accounts.first?.uid
        }
    }

    private func restoreAccount(uid: String) async throws -> AccountContext {
        guard let accessToken = KeychainStore.loadString(key: "accessToken", namespace: uid),
              let refreshToken = KeychainStore.loadString(key: "refreshToken", namespace: uid) else {
            throw AccountStoreError.missingCredentials
        }

        let ctx = AccountContext(uid: uid)
        await ctx.client.setAuth(uid: uid, accessToken: accessToken, refreshToken: refreshToken)

        try await AuthAPI.refresh(client: ctx.client)

        let userResp: UserResponse = try await ctx.client.get(path: "core/v4/users")
        ctx.user = userResp.user

        let addrResp: AddressesResponse = try await ctx.client.get(path: "core/v4/addresses")
        ctx.addresses = addrResp.addresses

        if let kp = KeychainStore.loadString(key: "keyPassphrase", namespace: uid) {
            ctx.keyPassphrase = kp
            loadDecryptorKeys(context: ctx, passphrase: kp)
        }

        try await saveSession(context: ctx)
        return ctx
    }

    // MARK: - Login

    public func loginNewAccount(username: String, password: String) async throws -> (context: AccountContext, needsTwoFactor: Bool) {
        let tempClient = ProtonClient()
        let result = try await AuthAPI.login(client: tempClient, username: username, password: password)

        let ctx = AccountContext(uid: result.uid)
        await ctx.client.setAuth(uid: result.uid, accessToken: result.accessToken, refreshToken: result.refreshToken)

        return (ctx, result.needsTwoFactor)
    }

    public func submit2FA(context: AccountContext, code: String) async throws {
        try await AuthAPI.submit2FA(client: context.client, code: code)
    }

    public func completeLogin(context: AccountContext, password: String) async throws {
        let userResp: UserResponse = try await context.client.get(path: "core/v4/users")
        context.user = userResp.user

        let saltsResp: SaltsResponse = try await context.client.get(path: "core/v4/keys/salts")
        let addrResp: AddressesResponse = try await context.client.get(path: "core/v4/addresses")
        context.addresses = addrResp.addresses

        if let primaryKey = userResp.user.primaryKey,
           let salt = saltsResp.keySalts.first(where: { $0.id == primaryKey.id }),
           let keySalt = salt.keySalt,
           let passphrase = KeyPassphrase.compute(password: password, keySalt: keySalt) {
            context.keyPassphrase = passphrase
            loadDecryptorKeys(context: context, passphrase: passphrase)
        }

        try await saveSession(context: context)
        addAccount(context)
    }

    // MARK: - Key Loading

    private func loadDecryptorKeys(context: AccountContext, passphrase: String) {
        var keyPairs: [(armoredKey: String, passphrase: String)] = []

        guard let user = context.user else { return }

        for userKey in user.keys {
            keyPairs.append((userKey.privateKey, passphrase))
        }

        let userPrimaryArmored = user.primaryKey?.privateKey
        for address in context.addresses {
            for addrKey in address.keys {
                let hasToken = addrKey.token != nil && !(addrKey.token?.isEmpty ?? true)
                if hasToken, let token = addrKey.token, let userArmored = userPrimaryArmored {
                    if let addrPassphrase = MessageDecryptor.decryptToken(token, userArmoredKey: userArmored, userPassphrase: passphrase) {
                        keyPairs.append((addrKey.privateKey, addrPassphrase))
                    } else {
                        keyPairs.append((addrKey.privateKey, passphrase))
                    }
                } else {
                    keyPairs.append((addrKey.privateKey, passphrase))
                }
            }
        }

        context.keyPairs = keyPairs
        try? context.decryptor.loadKeysWithPassphrases(keyPairs)
    }

    // MARK: - Session Save

    private func saveSession(context: AccountContext) async throws {
        let ns = context.uid
        try KeychainStore.save(key: "uid", string: ns, namespace: ns)
        if let at = await context.client.accessToken {
            try KeychainStore.save(key: "accessToken", string: at, namespace: ns)
        }
        if let rt = await context.client.refreshToken {
            try KeychainStore.save(key: "refreshToken", string: rt, namespace: ns)
        }
        if let kp = context.keyPassphrase {
            try KeychainStore.save(key: "keyPassphrase", string: kp, namespace: ns)
        }
    }

    // MARK: - Migration

    private func migrateIfNeeded() {
        guard let oldUID = KeychainStore.loadString(key: "uid"),
              KeychainStore.loadString(key: "uid", namespace: oldUID) == nil else {
            return
        }

        ProtonClient.debugLog("AccountStore: migrating legacy single-account keychain data for uid=\(oldUID)")

        if let at = KeychainStore.loadString(key: "accessToken") {
            try? KeychainStore.save(key: "accessToken", string: at, namespace: oldUID)
        }
        if let rt = KeychainStore.loadString(key: "refreshToken") {
            try? KeychainStore.save(key: "refreshToken", string: rt, namespace: oldUID)
        }
        if let kp = KeychainStore.loadString(key: "keyPassphrase") {
            try? KeychainStore.save(key: "keyPassphrase", string: kp, namespace: oldUID)
        }
        try? KeychainStore.save(key: "uid", string: oldUID, namespace: oldUID)

        let desc = AccountDescriptor(uid: oldUID, email: oldUID, displayName: nil)
        if let data = try? JSONEncoder().encode([desc]) {
            UserDefaults.standard.set(data, forKey: accountListKey)
        }

        KeychainStore.deleteAll()
    }

    // MARK: - Logout

    public func logoutAccount(uid: String) async {
        if let ctx = accounts.first(where: { $0.uid == uid }) {
            try? await AuthAPI.logout(client: ctx.client)
        }
        removeAccount(uid: uid)
    }

    public func logoutAll() async {
        for ctx in accounts {
            try? await AuthAPI.logout(client: ctx.client)
            KeychainStore.deleteAll(namespace: ctx.uid)
        }
        accounts.removeAll()
        activeAccountUID = nil
        UserDefaults.standard.removeObject(forKey: accountListKey)
    }

    public enum AccountStoreError: Error {
        case missingCredentials
    }
}
