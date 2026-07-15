import Foundation

/// Errors surfaced by the networking layer. `unauthorized` is special-cased by the UI to
/// route the user back to the login screen.
enum APIError: Error, LocalizedError, Equatable {
    case notConfigured              // GITHUB_CLIENT_ID missing
    case unauthorized               // 401 — token invalid/expired
    case forbidden(String?)         // 403 — often rate limiting or missing scope
    case rateLimited(resetAt: Date?)
    case notFound
    case http(status: Int, message: String?)
    case decoding(String)
    case transport(String)
    case deviceFlow(DeviceFlowError)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "GitHub Client ID is not configured. See README → Setup."
        case .unauthorized:
            return "Your GitHub session has expired. Please sign in again."
        case .forbidden(let msg):
            return msg ?? "Access forbidden. Check your token scopes."
        case .rateLimited(let reset):
            if let reset { return "GitHub rate limit reached. Resets \(reset.formatted(.relative(presentation: .named)))." }
            return "GitHub rate limit reached."
        case .notFound:
            return "Resource not found."
        case .http(let status, let message):
            return "GitHub returned HTTP \(status)." + (message.map { " \($0)" } ?? "")
        case .decoding(let detail):
            return "Failed to read GitHub response: \(detail)"
        case .transport(let detail):
            return "Network error: \(detail)"
        case .deviceFlow(let e):
            return e.errorDescription
        }
    }

    /// True when the error means the stored token should be discarded.
    var requiresReauth: Bool { self == .unauthorized }
}

/// Errors specific to the OAuth Device Flow polling loop.
enum DeviceFlowError: Error, Equatable {
    case authorizationPending       // keep polling
    case slowDown                   // back off, keep polling
    case expiredToken               // user waited too long — restart
    case accessDenied               // user rejected the request
    case unknown(String)

    var errorDescription: String {
        switch self {
        case .authorizationPending: return "Waiting for you to authorize in the browser…"
        case .slowDown: return "Slowing down polling…"
        case .expiredToken: return "The device code expired. Please restart sign-in."
        case .accessDenied: return "Authorization was denied."
        case .unknown(let s): return "Sign-in failed: \(s)"
        }
    }
}
