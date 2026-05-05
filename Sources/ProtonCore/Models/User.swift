import Foundation

public struct ProtonUser: Decodable {
    public let id: String
    public let name: String?
    public let displayName: String?
    public let email: String?
    public let keys: [UserKey]
    public let usedSpace: Int64?
    public let maxSpace: Int64?

    public struct UserKey: Decodable {
        public let id: String
        public let privateKey: String
        public let active: Int
        public let primary: Int

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case privateKey = "PrivateKey"
            case active = "Active"
            case primary = "Primary"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case displayName = "DisplayName"
        case email = "Email"
        case keys = "Keys"
        case usedSpace = "UsedSpace"
        case maxSpace = "MaxSpace"
    }

    public var primaryKey: UserKey? {
        keys.first { $0.primary == 1 } ?? keys.first
    }
}

public struct UserResponse: Decodable {
    public let code: Int
    public let user: ProtonUser

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case user = "User"
    }
}

public struct Salt: Decodable {
    public let id: String
    public let keySalt: String?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case keySalt = "KeySalt"
    }
}

public struct SaltsResponse: Decodable {
    public let code: Int
    public let keySalts: [Salt]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case keySalts = "KeySalts"
    }
}
