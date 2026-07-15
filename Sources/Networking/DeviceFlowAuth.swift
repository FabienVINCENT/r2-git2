import Foundation

/// Implements GitHub's OAuth **Device Flow** (no client secret).
/// See: https://docs.github.com/apps/oauth-apps/building-oauth-apps/authorizing-oauth-apps#device-flow
///
/// Usage: `requestCode()` to get a user code to display, then poll `pollForToken(deviceCode:)`
/// on the returned interval until it yields a token or throws a terminal `DeviceFlowError`.
struct DeviceFlowAuth: Sendable {

    private let session: URLSession
    private let clientID: String

    init(clientID: String = Config.githubClientID, session: URLSession = .shared) {
        self.clientID = clientID
        self.session = session
    }

    struct DeviceCode: Sendable, Decodable {
        let deviceCode: String
        let userCode: String
        let verificationURI: URL
        let expiresIn: Int
        let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code"
            case userCode = "user_code"
            case verificationURI = "verification_uri"
            case expiresIn = "expires_in"
            case interval
        }
    }

    /// Step 1 — ask GitHub for a device + user code.
    func requestCode() async throws -> DeviceCode {
        guard Config.isClientIDConfigured else { throw APIError.notConfigured }

        var req = URLRequest(url: Config.deviceCodeURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = formBody([
            "client_id": clientID,
            "scope": Config.oauthScopes.joined(separator: " "),
        ])

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw APIError.transport("Could not start device flow.")
        }
        do {
            return try JSONDecoder().decode(DeviceCode.self, from: data)
        } catch {
            throw APIError.decoding("\(error)")
        }
    }

    /// Step 2 — one poll attempt. Returns the access token on success, or throws a
    /// `DeviceFlowError` (`.authorizationPending` / `.slowDown` mean "keep polling").
    func pollForToken(deviceCode: String) async throws -> String {
        var req = URLRequest(url: Config.deviceTokenURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        req.httpBody = formBody([
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])

        let (data, _) = try await session.data(for: req)

        struct TokenResponse: Decodable {
            let accessToken: String?
            let error: String?
            enum CodingKeys: String, CodingKey { case accessToken = "access_token"; case error }
        }

        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw APIError.deviceFlow(.unknown("Unexpected token response."))
        }
        if let token = decoded.accessToken { return token }

        switch decoded.error {
        case "authorization_pending": throw APIError.deviceFlow(.authorizationPending)
        case "slow_down": throw APIError.deviceFlow(.slowDown)
        case "expired_token": throw APIError.deviceFlow(.expiredToken)
        case "access_denied": throw APIError.deviceFlow(.accessDenied)
        default: throw APIError.deviceFlow(.unknown(decoded.error ?? "unknown"))
        }
    }

    private func formBody(_ params: [String: String]) -> Data {
        params.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryValueAllowed) ?? value
            return "\(key)=\(v)"
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }
}

private extension CharacterSet {
    /// URL query value encoding — stricter than `.urlQueryAllowed` (encodes `&`, `=`, `+`).
    static let urlQueryValueAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
