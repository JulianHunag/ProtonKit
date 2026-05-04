import Foundation

public enum MessageAPI {
    public static func list(
        client: ProtonClient,
        labelID: String = "0",
        page: Int = 0,
        pageSize: Int = 50,
        sort: String = "Time",
        desc: Bool = true,
        keyword: String? = nil
    ) async throws -> MessagesResponse {
        let descParam = desc ? 1 : 0
        var path = "mail/v4/messages?LabelID=\(labelID)&Page=\(page)&PageSize=\(pageSize)&Sort=\(sort)&Desc=\(descParam)"
        if let keyword, !keyword.isEmpty,
           let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            path += "&Keyword=\(encoded)"
        }
        return try await client.get(path: path)
    }

    public static func get(client: ProtonClient, messageID: String) async throws -> MessageResponse {
        return try await client.get(path: "mail/v4/messages/\(messageID)")
    }

    public static func markRead(client: ProtonClient, messageIDs: [String]) async throws {
        struct Req: Encodable { let IDs: [String] }
        struct Resp: Decodable { let Code: Int }
        let _: Resp = try await client.put(path: "mail/v4/messages/read", body: Req(IDs: messageIDs))
    }

    public static func markUnread(client: ProtonClient, messageIDs: [String]) async throws {
        struct Req: Encodable { let IDs: [String] }
        struct Resp: Decodable { let Code: Int }
        let _: Resp = try await client.put(path: "mail/v4/messages/unread", body: Req(IDs: messageIDs))
    }

    public static func downloadAttachment(client: ProtonClient, attachmentID: String) async throws -> Data {
        try await client.getRawData(path: "mail/v4/attachments/\(attachmentID)")
    }

    public static func trash(client: ProtonClient, messageIDs: [String]) async throws {
        struct Req: Encodable {
            let IDs: [String]
            let LabelID: String
        }
        struct Resp: Decodable { let Code: Int }
        let _: Resp = try await client.put(
            path: "mail/v4/messages/label",
            body: Req(IDs: messageIDs, LabelID: SystemLabel.trash.rawValue)
        )
    }
}
