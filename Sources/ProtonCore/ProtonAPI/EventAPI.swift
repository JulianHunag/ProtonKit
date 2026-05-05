import Foundation

public enum EventAPI {
    public static func getLatestEventID(client: ProtonClient) async throws -> String {
        let resp: LatestEventResponse = try await client.get(path: "core/v4/events/latest")
        return resp.eventID
    }

    public static func getEvents(client: ProtonClient, eventID: String) async throws -> EventResponse {
        return try await client.get(path: "core/v4/events/\(eventID)")
    }
}
