import Foundation

public enum ProtonAPIError: Error, LocalizedError {
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)
    case networkError(Error)
    case unauthorized
    case tooManyRequests(retryAfter: Int?)
    case apiError(code: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let msg):
            return "HTTP \(code): \(msg ?? "Unknown error")"
        case .decodingError(let err):
            return "Decoding error: \(err.localizedDescription)"
        case .networkError(let err):
            return "Network error: \(err.localizedDescription)"
        case .unauthorized:
            return "Unauthorized - session expired"
        case .tooManyRequests(let retry):
            return "Rate limited, retry after \(retry ?? 60)s"
        case .apiError(let code, let msg):
            return "API error \(code): \(msg)"
        }
    }
}

struct ProtonAPIResponse<T: Decodable>: Decodable {
    let code: Int
    let error: String?

    enum CodingKeys: String, CodingKey {
        case code = "Code"
        case error = "Error"
    }
}
