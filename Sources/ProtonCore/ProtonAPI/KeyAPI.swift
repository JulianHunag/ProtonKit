import Foundation

public struct RecipientKeyResponse: Decodable, Sendable {
    public let code: Int
    public let recipientType: Int
    public let mimeType: String?
    public let keys: [RecipientKey]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case recipientType = "RecipientType"
        case mimeType = "MIMEType"
        case keys = "Keys"
    }

    public struct RecipientKey: Decodable, Sendable {
        public let flags: Int
        public let publicKey: String

        enum CodingKeys: String, CodingKey {
            case flags = "Flags"
            case publicKey = "PublicKey"
        }
    }
}

public enum KeyAPI {
    public static func getPublicKeys(
        client: ProtonClient,
        email: String
    ) async throws -> RecipientKeyResponse {
        let encoded = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? email
        return try await client.get(path: "core/v4/keys?Email=\(encoded)")
    }
}
