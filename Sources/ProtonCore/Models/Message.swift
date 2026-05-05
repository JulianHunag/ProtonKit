import Foundation

public struct EmailAddress: Codable {
    public let name: String?
    public let address: String

    enum CodingKeys: String, CodingKey {
        case name = "Name"
        case address = "Address"
    }

    public init(name: String? = nil, address: String) {
        self.name = name
        self.address = address
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

// MARK: - Send models

public struct SessionKey: Encodable {
    public let key: String
    public let algorithm: String

    enum CodingKeys: String, CodingKey {
        case key = "Key"
        case algorithm = "Algorithm"
    }

    public init(key: String, algorithm: String) {
        self.key = key
        self.algorithm = algorithm
    }
}

public struct SendPackage: Encodable {
    public let addresses: [String: SendAddress]
    public let mimeType: String
    public let body: String
    public let packageType: Int
    public let bodyKey: SessionKey?
    public let attachmentKeys: [String: SessionKey]?

    enum CodingKeys: String, CodingKey {
        case addresses = "Addresses"
        case mimeType = "MIMEType"
        case body = "Body"
        case packageType = "Type"
        case bodyKey = "BodyKey"
        case attachmentKeys = "AttachmentKeys"
    }

    public init(addresses: [String: SendAddress], mimeType: String, body: String, type: Int, bodyKey: SessionKey? = nil, attachmentKeys: [String: SessionKey]? = nil) {
        self.addresses = addresses
        self.mimeType = mimeType
        self.body = body
        self.packageType = type
        self.bodyKey = bodyKey
        self.attachmentKeys = attachmentKeys
    }
}

public struct SendAddress: Encodable {
    public let addressType: Int
    public let bodyKeyPacket: String
    public let signature: Int
    public let attachmentKeyPackets: [String: String]?

    enum CodingKeys: String, CodingKey {
        case addressType = "Type"
        case bodyKeyPacket = "BodyKeyPacket"
        case signature = "Signature"
        case attachmentKeyPackets = "AttachmentKeyPackets"
    }

    public init(type: Int, bodyKeyPacket: String, signature: Int = 0, attachmentKeyPackets: [String: String]? = nil) {
        self.addressType = type
        self.bodyKeyPacket = bodyKeyPacket
        self.signature = signature
        self.attachmentKeyPackets = attachmentKeyPackets
    }
}

public struct SendResponse: Decodable {
    public let code: Int
    public let sent: FullMessage?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case sent = "Sent"
    }
}

// MARK: - List/Get responses

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

public struct AttachmentResponse: Decodable {
    public let code: Int
    public let attachment: AttachmentMeta

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case attachment = "Attachment"
    }

    public struct AttachmentMeta: Decodable {
        public let id: String

        enum CodingKeys: String, CodingKey {
            case id = "ID"
        }
    }
}
