import Foundation

public struct ProtonLabel: Decodable, Identifiable {
    public let id: String
    public let name: String
    public let type: Int
    public let color: String?
    public let order: Int

    enum CodingKeys: String, CodingKey {
        case id = "ID"
        case name = "Name"
        case type = "Type"
        case color = "Color"
        case order = "Order"
    }
}

public struct LabelsResponse: Decodable {
    public let code: Int
    public let labels: [ProtonLabel]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case labels = "Labels"
    }
}

public struct MessageCount: Decodable {
    public let labelID: String
    public let total: Int
    public let unread: Int

    enum CodingKeys: String, CodingKey {
        case labelID = "LabelID"
        case total = "Total"
        case unread = "Unread"
    }
}

public struct MessageCountsResponse: Decodable {
    public let code: Int
    public let counts: [MessageCount]

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case counts = "Counts"
    }
}

public enum SystemLabel: String {
    case inbox = "0"
    case allDrafts = "1"
    case allSent = "2"
    case trash = "3"
    case spam = "4"
    case allMail = "5"
    case archive = "6"
    case sent = "7"
    case drafts = "8"
    case starred = "10"

    public var displayName: String {
        switch self {
        case .inbox: return "Inbox"
        case .allDrafts, .drafts: return "Drafts"
        case .allSent, .sent: return "Sent"
        case .trash: return "Trash"
        case .spam: return "Spam"
        case .allMail: return "All Mail"
        case .archive: return "Archive"
        case .starred: return "Starred"
        }
    }
}
