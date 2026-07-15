import Foundation

/// Central place that turns a relative REST path into an absolute URL against the configured
/// base. Isolating this here is what makes a future **GitHub Enterprise** switch a one-line
/// change (point `Config.apiBaseURL` / `Config.graphQLURL` at the Enterprise host).
enum GitHubEndpoint {

    /// Builds a REST URL: `<apiBaseURL>/<path>?<query>`.
    static func rest(_ path: String, query: [URLQueryItem] = []) -> URL {
        let trimmed = path.hasPrefix("/") ? String(path.dropFirst()) : path
        var components = URLComponents(
            url: Config.apiBaseURL.appendingPathComponent(trimmed),
            resolvingAgainstBaseURL: false
        )!
        if !query.isEmpty { components.queryItems = query }
        return components.url!
    }

    static var graphQL: URL { Config.graphQLURL }
}
