import Foundation

public actor ProtonClient {
    static let baseURL = URL(string: "https://mail.proton.me/api")!
    private let session: URLSession
    public private(set) var uid: String?
    public private(set) var accessToken: String?
    public private(set) var refreshToken: String?

    public nonisolated static func debugLog(_ msg: String) {
        #if DEBUG
        print("[ProtonKit] \(msg)")
        #endif
    }

    public init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        self.session = URLSession(configuration: config)
    }

    public func setAuth(uid: String, accessToken: String, refreshToken: String) {
        self.uid = uid
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    public func clearAuth() {
        self.uid = nil
        self.accessToken = nil
        self.refreshToken = nil
    }

    public var isAuthenticated: Bool {
        accessToken != nil
    }

    public func request<T: Decodable>(
        method: String,
        path: String,
        body: (any Encodable)? = nil,
        authenticated: Bool = true
    ) async throws -> T {
        let url = URL(string: Self.baseURL.absoluteString + "/" + path)!
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Other", forHTTPHeaderField: "x-pm-appversion")

        if authenticated, let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid {
            req.setValue(uid, forHTTPHeaderField: "x-pm-uid")
        }

        if let body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ProtonAPIError.networkError(error)
        }

        guard let httpResp = response as? HTTPURLResponse else {
            throw ProtonAPIError.networkError(URLError(.badServerResponse))
        }

        if httpResp.statusCode == 401 {
            throw ProtonAPIError.unauthorized
        }
        if httpResp.statusCode == 429 {
            let retryAfter = httpResp.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            throw ProtonAPIError.tooManyRequests(retryAfter: retryAfter)
        }

        Self.debugLog("\(method) /\(path) → \(httpResp.statusCode) (\(data.count) bytes)")
        if path.contains("messages") || path.contains("Messages") {
            if let raw = String(data: data.prefix(500), encoding: .utf8) {
                Self.debugLog("  messages raw: \(raw)")
            }
        }

        guard (200..<300).contains(httpResp.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            Self.debugLog("  HTTP error body: \(errorMsg ?? "nil")")
            throw ProtonAPIError.httpError(statusCode: httpResp.statusCode, message: errorMsg)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.debugLog("  Decode \(T.self) FAILED: \(error)")
            if let raw = String(data: data.prefix(500), encoding: .utf8) {
                Self.debugLog("  Raw: \(raw)")
            }
            throw ProtonAPIError.decodingError(error)
        }
    }

    public func getRawData(path: String) async throws -> Data {
        let url = URL(string: Self.baseURL.absoluteString + "/" + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Other", forHTTPHeaderField: "x-pm-appversion")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid {
            req.setValue(uid, forHTTPHeaderField: "x-pm-uid")
        }
        let (data, response) = try await session.data(for: req)
        guard let httpResp = response as? HTTPURLResponse,
              (200..<300).contains(httpResp.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw ProtonAPIError.httpError(statusCode: code, message: nil)
        }
        Self.debugLog("GET(raw) /\(path) → \(httpResp.statusCode) (\(data.count) bytes)")
        return data
    }

    public func uploadMultipart<T: Decodable>(
        path: String,
        fields: [(name: String, value: String)],
        fileField: String,
        fileName: String,
        mimeType: String,
        fileData: Data
    ) async throws -> T {
        let boundary = "Boundary-\(UUID().uuidString)"
        let url = URL(string: Self.baseURL.absoluteString + "/" + path)!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.setValue("Other", forHTTPHeaderField: "x-pm-appversion")
        if let token = accessToken {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let uid {
            req.setValue(uid, forHTTPHeaderField: "x-pm-uid")
        }

        var body = Data()
        for field in fields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(field.name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(field.value)\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"\(fileField)\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body

        let (data, response) = try await session.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else {
            throw ProtonAPIError.networkError(URLError(.badServerResponse))
        }

        Self.debugLog("POST(multipart) /\(path) → \(httpResp.statusCode) (\(data.count) bytes)")

        guard (200..<300).contains(httpResp.statusCode) else {
            let errorMsg = String(data: data, encoding: .utf8)
            Self.debugLog("  HTTP error body: \(errorMsg ?? "nil")")
            throw ProtonAPIError.httpError(statusCode: httpResp.statusCode, message: errorMsg)
        }

        return try JSONDecoder().decode(T.self, from: data)
    }

    public func get<T: Decodable>(path: String, authenticated: Bool = true) async throws -> T {
        try await request(method: "GET", path: path, authenticated: authenticated)
    }

    public func post<T: Decodable>(path: String, body: (any Encodable)? = nil, authenticated: Bool = true) async throws -> T {
        try await request(method: "POST", path: path, body: body, authenticated: authenticated)
    }

    public func put<T: Decodable>(path: String, body: (any Encodable)? = nil) async throws -> T {
        try await request(method: "PUT", path: path, body: body)
    }

    public func delete<T: Decodable>(path: String) async throws -> T {
        try await request(method: "DELETE", path: path)
    }
}
