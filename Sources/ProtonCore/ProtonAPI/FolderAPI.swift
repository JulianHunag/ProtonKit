import Foundation

public enum FolderAPI {
    public static func list(client: ProtonClient) async throws -> LabelsResponse {
        return try await client.get(path: "core/v4/labels?Type=3")
    }

    public static func messageCounts(client: ProtonClient) async throws -> MessageCountsResponse {
        return try await client.get(path: "mail/v4/messages/count")
    }
}
