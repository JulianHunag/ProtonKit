import Foundation

public struct AuthInfoRequest: Encodable, Sendable {
    public let Username: String
    public init(Username: String) { self.Username = Username }
}

public struct AuthInfoResponse: Decodable, Sendable {
    public let code: Int
    public let modulus: String
    public let serverEphemeral: String
    public let version: Int
    public let salt: String
    public let srpSession: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case modulus = "Modulus"
        case serverEphemeral = "ServerEphemeral"
        case version = "Version"
        case salt = "Salt"
        case srpSession = "SRPSession"
    }
}

public struct AuthRequest: Encodable, Sendable {
    public let Username: String
    public let ClientEphemeral: String
    public let ClientProof: String
    public let SRPSession: String
}

public struct TwoFARequest: Encodable, Sendable {
    public let TwoFactorCode: String
}

public struct TwoFAResponse: Decodable, Sendable {
    public let code: Int

    enum CodingKeys: String, CodingKey {
        case code = "Code"
    }
}

public struct AuthResponse: Decodable, Sendable {
    public let code: Int
    public let uid: String
    public let accessToken: String
    public let refreshToken: String
    public let serverProof: String
    public let scopes: [String]
    public let userID: String
    public let twoFactor: TwoFactorInfo?

    public struct TwoFactorInfo: Decodable, Sendable {
        public let enabled: Int
        public let totp: Int?

        enum CodingKeys: String, CodingKey {
            case enabled = "Enabled"
            case totp = "TOTP"
        }
    }

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case uid = "UID"
        case accessToken = "AccessToken"
        case refreshToken = "RefreshToken"
        case serverProof = "ServerProof"
        case scopes = "Scopes"
        case userID = "UserID"
        case twoFactor = "2FA"
    }
}

struct RefreshRequest: Encodable, Sendable {
    let UID: String
    let RefreshToken: String
    let GrantType: String = "refresh_token"
    let ResponseType: String = "token"
    let RedirectURI: String = "https://protonmail.ch"
}

struct RefreshResponse: Decodable, Sendable {
    let code: Int
    let accessToken: String
    let refreshToken: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case accessToken = "AccessToken"
        case refreshToken = "RefreshToken"
    }
}
