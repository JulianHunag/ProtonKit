import Foundation

public struct LoginResult {
    public let needsTwoFactor: Bool
    public let uid: String
    public let accessToken: String
    public let refreshToken: String
    public let serverProof: String
    public let userID: String
}

public enum AuthAPI {
    public static func login(
        client: ProtonClient,
        username: String,
        password: String
    ) async throws -> LoginResult {
        let infoReq = AuthInfoRequest(Username: username)
        let info: AuthInfoResponse = try await client.post(
            path: "auth/info",
            body: infoReq,
            authenticated: false
        )

        let srpResult = try SRPClient.generateSRP(password: password, authInfo: info)

        let authReq = AuthRequest(
            Username: username,
            ClientEphemeral: srpResult.clientEphemeral,
            ClientProof: srpResult.clientProof,
            SRPSession: info.srpSession
        )
        let authResp: AuthResponse = try await client.post(
            path: "auth",
            body: authReq,
            authenticated: false
        )

        guard SRPClient.verifyServerProof(
            authResp.serverProof,
            expected: srpResult.expectedServerProof
        ) else {
            throw SRPError.invalidServerEphemeral
        }

        await client.setAuth(
            uid: authResp.uid,
            accessToken: authResp.accessToken,
            refreshToken: authResp.refreshToken
        )

        let needsTwoFA = (authResp.twoFactor?.enabled ?? 0) > 0
        return LoginResult(
            needsTwoFactor: needsTwoFA,
            uid: authResp.uid,
            accessToken: authResp.accessToken,
            refreshToken: authResp.refreshToken,
            serverProof: authResp.serverProof,
            userID: authResp.userID
        )
    }

    public static func submit2FA(
        client: ProtonClient,
        code: String
    ) async throws {
        let req = TwoFARequest(TwoFactorCode: code)
        let _: TwoFAResponse = try await client.post(path: "auth/2fa", body: req)
    }

    public static func logout(client: ProtonClient) async throws {
        struct Empty: Decodable {}
        let _: Empty = try await client.delete(path: "auth")
        await client.clearAuth()
    }

    public static func refresh(client: ProtonClient) async throws {
        guard let uid = await client.uid,
              let refreshToken = await client.refreshToken else {
            throw ProtonAPIError.unauthorized
        }

        let req = RefreshRequest(UID: uid, RefreshToken: refreshToken)
        let resp: RefreshResponse = try await client.post(
            path: "auth/refresh",
            body: req,
            authenticated: false
        )

        await client.setAuth(
            uid: uid,
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken
        )
    }
}
