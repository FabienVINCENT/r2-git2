import Foundation

/// Errors surfaced by the networking layer. `unauthorized` is special-cased by the UI to
/// route the user back to the login screen.
enum APIError: Error, LocalizedError, Equatable {
    case unauthorized               // 401 — token invalid/expired
    case forbidden(String?)         // 403 — often rate limiting or missing scope
    case rateLimited(resetAt: Date?)
    case notFound
    case http(status: Int, message: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
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
        }
    }

    /// True when the error means the stored token should be discarded.
    var requiresReauth: Bool { self == .unauthorized }
}
