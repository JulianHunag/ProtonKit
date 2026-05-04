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

    // MARK: - Draft & Send

    public static func createDraft(
        client: ProtonClient,
        subject: String,
        body: String,
        mimeType: String = "text/html",
        senderAddressID: String,
        senderName: String,
        senderAddress: String,
        toList: [EmailAddress],
        ccList: [EmailAddress] = [],
        bccList: [EmailAddress] = [],
        parentID: String? = nil,
        action: Int? = nil
    ) async throws -> MessageResponse {
        struct Msg: Encodable {
            let Subject: String
            let Body: String
            let MIMEType: String
            let Sender: Addr
            let ToList: [Addr]
            let CCList: [Addr]
            let BCCList: [Addr]
            let AddressID: String
        }
        struct Addr: Encodable {
            let Name: String
            let Address: String
        }
        struct Req: Encodable {
            let Message: Msg
            let ParentID: String?
            let Action: Int?
        }
        let req = Req(
            Message: Msg(
                Subject: subject,
                Body: body,
                MIMEType: mimeType,
                Sender: Addr(Name: senderName, Address: senderAddress),
                ToList: toList.map { Addr(Name: $0.name ?? "", Address: $0.address) },
                CCList: ccList.map { Addr(Name: $0.name ?? "", Address: $0.address) },
                BCCList: bccList.map { Addr(Name: $0.name ?? "", Address: $0.address) },
                AddressID: senderAddressID
            ),
            ParentID: parentID,
            Action: action
        )
        return try await client.post(path: "mail/v4/messages", body: req)
    }

    public static func sendMessage(
        client: ProtonClient,
        messageID: String,
        packages: [SendPackage]
    ) async throws -> SendResponse {
        struct Req: Encodable {
            let Packages: [SendPackage]
        }
        return try await client.post(
            path: "mail/v4/messages/\(messageID)",
            body: Req(Packages: packages)
        )
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
