import Foundation

public struct ProtonAddress: Decodable {
    public let id: String
    public let email: String
    public let status: Int
    public let order: Int
    public let keys: [AddressKey]

    public struct AddressKey: Decodable {
        public let id: String
        public let privateKey: String
        public let flags: Int
        public let primary: Int
        public let token: String?
        public let signature: String?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case privateKey = "PrivateKey"
            case flags = "Flags"
            case primary = "Primary"
            case token = "Token"
            case signature = "Signature"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case email = "Email"
        case status = "Status"
        case order = "Order"
        case keys = "Keys"
    }

    public var primaryKey: AddressKey? {
        keys.first { $0.primary == 1 } ?? keys.first
    }
}

public struct AddressesResponse: Decodable {
    public let code: Int
    public let addresses: [ProtonAddress]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case addresses = "Addresses"
    }
}
