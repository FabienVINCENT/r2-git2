import Foundation

/// Global, compile-time configuration.
///
/// Fill in `githubClientID` with the Client ID of the OAuth App you register on GitHub
/// (Settings → Developer settings → OAuth Apps → New OAuth App).
/// The Device Flow does **not** use a client secret, so nothing secret is embedded here.
enum Config {

    // MARK: - GitHub OAuth (Device Flow)

    /// OAuth App Client ID. REQUIRED — the app shows an error on the login screen until set.
    /// Register at https://github.com/settings/developers and enable "Device Flow".
    static let githubClientID = "REPLACE_WITH_GITHUB_CLIENT_ID"

    /// Scopes requested during authorization.
    /// - `repo`           read PRs / Actions on private + public repos
    /// - `read:org`       enumerate organizations you belong to
    /// - `notifications`  read the notifications inbox (mentions)
    static let oauthScopes = ["repo", "read:org", "notifications"]

    // MARK: - GitHub API base URLs (Enterprise-ready)

    /// REST + Search base. For GitHub Enterprise Server this becomes `https://HOST/api/v3`.
    static let apiBaseURL = URL(string: "https://api.github.com")!

    /// GraphQL endpoint. For Enterprise: `https://HOST/api/graphql`.
    static let graphQLURL = URL(string: "https://api.github.com/graphql")!

    /// Device Flow endpoints live on the web host, not the API host.
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")!
    static let deviceTokenURL = URL(string: "https://github.com/login/oauth/access_token")!

    /// Where users type the code shown by the login screen.
    static let deviceVerificationURL = URL(string: "https://github.com/login/device")!

    // MARK: - Behavior

    /// Available auto-refresh intervals (seconds). Default is 10 minutes, per spec.
    static let refreshIntervals: [TimeInterval] = [300, 600, 900, 1800]
    static let defaultRefreshInterval: TimeInterval = 600

    /// How far back "recent" Actions runs go.
    static let recentRunsWindow: TimeInterval = 24 * 60 * 60

    /// A friendly User-Agent is required by the GitHub API.
    static let userAgent = "r2-git2/1.0 (macOS menu bar app)"

    static var isClientIDConfigured: Bool { githubClientID != "REPLACE_WITH_GITHUB_CLIENT_ID" && !githubClientID.isEmpty }
}
