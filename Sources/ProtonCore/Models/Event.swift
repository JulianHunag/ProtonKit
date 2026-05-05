import Foundation

public struct EventResponse: Decodable {
    public let code: Int
    public let eventID: String
    public let more: Int
    public let messages: [MessageEvent]?
    public let messageCounts: [MessageCount]?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case eventID = "EventID"
        case more = "More"
        case messages = "Messages"
        case messageCounts = "MessageCounts"
    }
}

public struct MessageEvent: Decodable {
    public let id: String
    public let action: Int
    public let message: MessageMetadata?

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case action = "Action"
        case message = "Message"
    }

    public enum Action: Int {
        case delete = 0
        case create = 1
        case update = 2
        case updateFlags = 3
    }
}

public struct LatestEventResponse: Decodable {
    public let code: Int
    public let eventID: String

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case eventID = "EventID"
    }
}
