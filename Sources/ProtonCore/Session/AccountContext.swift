import Foundation

public struct AccountDescriptor: Codable, Identifiable, Equatable {
    public let uid: String
    public let email: String
    public let displayName: String?

    public var id: String { uid }

    public init(uid: String, email: String, displayName: String?) {
        self.uid = uid
        self.email = email
        self.displayName = displayName
    }
}

@MainActor
public final class AccountContext: Identifiable, ObservableObject {
    public let uid: String
    public let client: ProtonClient
    public var user: ProtonUser?
    public var addresses: [ProtonAddress] = []
    public let decryptor = MessageDecryptor()
    public var keyPassphrase: String?
    public var keyPairs: [(armoredKey: String, passphrase: String)] = []

    public var id: String { uid }

    public var email: String {
        user?.email ?? addresses.first?.email ?? uid
    }

    public var displayName: String {
        user?.displayName ?? user?.name ?? email
    }

    public init(uid: String) {
        self.uid = uid
        self.client = ProtonClient()
    }

    public var descriptor: AccountDescriptor {
        AccountDescriptor(uid: uid, email: email, displayName: user?.displayName)
    }
}
