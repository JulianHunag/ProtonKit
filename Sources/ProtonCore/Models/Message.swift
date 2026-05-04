import Foundation

public struct EmailAddress: Decodable {
    public let name: String?
    public let address: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case address = "Address"
    }
}

public struct MessageMetadata: Decodable, Identifiable {
    public let id: String
    public let subject: String
    public let sender: EmailAddress
    public let toList: [EmailAddress]
    public let ccList: [EmailAddress]
    public let time: TimeInterval
    public let size: Int
    public var unread: Int
    public let labelIDs: [String]
    public let numAttachments: Int

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case subject = "Subject"
        case sender = "Sender"
        case toList = "ToList"
        case ccList = "CCList"
        case time = "Time"
        case size = "Size"
        case unread = "Unread"
        case labelIDs = "LabelIDs"
        case numAttachments = "NumAttachments"
    }

    public var senderName: String { sender.name ?? sender.address }
    public var senderAddress: String { sender.address }

    public var date: Date {
        Date(timeIntervalSince1970: time)
    }
}

public struct FullMessage: Decodable {
    public let id: String
    public let subject: String
    public let sender: EmailAddress
    public let toList: [EmailAddress]
    public let ccList: [EmailAddress]
    public let bccList: [EmailAddress]
    public let time: TimeInterval
    public let body: String
    public let mimeType: String?
    public let unread: Int
    public let labelIDs: [String]
    public let attachments: [Attachment]
    public let addressID: String

    public struct Attachment: Decodable, Identifiable {
        public let id: String
        public let name: String
        public let size: Int
        public let mimeType: String
        public let keyPackets: String?

        enum CodingKeys: String, CodingKey {
            case id = "ID"
            case name = "Name"
            case size = "Size"
            case mimeType = "MIMEType"
            case keyPackets = "KeyPackets"
        }
    }

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case subject = "Subject"
        case sender = "Sender"
        case toList = "ToList"
        case ccList = "CCList"
        case bccList = "BCCList"
        case time = "Time"
        case body = "Body"
        case mimeType = "MIMEType"
        case unread = "Unread"
        case labelIDs = "LabelIDs"
        case attachments = "Attachments"
        case addressID = "AddressID"
    }

    public var senderName: String { sender.name ?? sender.address }
    public var senderAddress: String { sender.address }
}

public struct MessagesResponse: Decodable {
    public let code: Int
    public let total: Int
    public let messages: [MessageMetadata]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case total = "Total"
        case messages = "Messages"
    }
}

public struct MessageResponse: Decodable {
    public let code: Int
    public let message: FullMessage

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case message = "Message"
    }
}
