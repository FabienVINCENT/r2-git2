import Foundation

/// Global, compile-time configuration.
///
/// Authentication uses a **Personal Access Token (classic)** that the user generates and pastes
/// in — this avoids the OAuth per-organization "grant" screen while keeping full API access
/// (cross-repo PR search, notifications inbox, org repos). Nothing secret is embedded here.
enum Config {

    // MARK: - GitHub token

    /// Scopes the pasted token must have: read PRs/Actions on private+public repos, list orgs,
    /// read the notifications inbox.
    static let requiredScopes = ["repo", "read:org", "notifications"]

    /// "New personal access token (classic)" page with our scopes pre-checked.
    static var tokenCreationURL: URL {
        URL(string: "https://github.com/settings/tokens/new?description=r2-git2&scopes=\(requiredScopes.joined(separator: ","))")!
    }

    // MARK: - GitHub API base URLs (Enterprise-ready)

    /// REST + Search base. For GitHub Enterprise Server this becomes `https://HOST/api/v3`.
    static let apiBaseURL = URL(string: "https://api.github.com")!

    /// GraphQL endpoint. For Enterprise: `https://HOST/api/graphql`.
    static let graphQLURL = URL(string: "https://api.github.com/graphql")!

    // MARK: - Behavior

    /// Available auto-refresh intervals (seconds). Default is 10 minutes, per spec.
    static let refreshIntervals: [TimeInterval] = [300, 600, 900, 1800]
    static let defaultRefreshInterval: TimeInterval = 600

    /// How far back a *failed* Actions run is still surfaced (successful runs are never listed —
    /// they're noise). Running/queued runs are always shown regardless of age.
    static let recentFailureWindow: TimeInterval = 6 * 60 * 60

    /// A friendly User-Agent is required by the GitHub API.
    static let userAgent = "r2-git2/1.0 (macOS menu bar app)"
}
