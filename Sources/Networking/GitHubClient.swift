import Foundation

/// Thin async GitHub API client. Actor-isolated so the token and rate-limit state are safe to
/// share across concurrent refresh tasks.
///
/// - REST for user, orgs, repo discovery, Actions runs, notifications, rate limit.
/// - GraphQL for PRs, because a single call returns each PR **with** its CI `statusCheckRollup`,
///   avoiding one extra REST call per PR (a big rate-limit win).
/// - All GET requests are conditional (`If-None-Match`); a 304 replays the cached body for free.
actor GitHubClient {

    private let session: URLSession
    private let cache: ETagCache
    private var token: String?
    private(set) var rateLimit: RateLimitInfo = .unknown

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(token: String?, cache: ETagCache, session: URLSession = .shared) {
        self.token = token
        self.cache = cache
        self.session = session
    }

    func setToken(_ token: String?) { self.token = token }
    var hasToken: Bool { token != nil }

    // MARK: - Core request

    /// Performs a request, applying auth, conditional headers and rate-limit bookkeeping.
    /// Returns the body bytes (from network on 200, or from cache on 304).
    private func send(
        method: String,
        url: URL,
        accept: String,
        body: Data? = nil,
        cacheKey: String? = nil
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        guard let token else { throw APIError.unauthorized }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue(accept, forHTTPHeaderField: "Accept")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let cacheKey, let etag = await cache.etag(forKey: cacheKey) {
            req.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("Non-HTTP response.")
        }

        updateRateLimit(from: http)

        switch http.statusCode {
        case 200, 201:
            if let cacheKey {
                let etag = http.value(forHTTPHeaderField: "ETag")
                await cache.update(key: cacheKey, etag: etag, data: data)
            }
            return (data, http)
        case 304:
            guard let cacheKey, let cached = await cache.data(forKey: cacheKey) else {
                // We were told "not modified" but lost the body — treat as empty success.
                return (Data(), http)
            }
            return (cached, http)
        case 401:
            throw APIError.unauthorized
        case 403:
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" {
                throw APIError.rateLimited(resetAt: resetDate(from: http))
            }
            throw APIError.forbidden(String(data: data, encoding: .utf8))
        case 404:
            throw APIError.notFound
        default:
            throw APIError.http(status: http.statusCode, message: String(data: data, encoding: .utf8))
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do { return try decoder.decode(T.self, from: data) }
        catch { throw APIError.decoding("\(error)") }
    }

    // MARK: - REST helpers

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = [], accept: String = "application/vnd.github+json", cache useCache: Bool = true) async throws -> T {
        let url = GitHubEndpoint.rest(path, query: query)
        let key = useCache ? "GET \(url.absoluteString)" : nil
        let (data, _) = try await send(method: "GET", url: url, accept: accept, cacheKey: key)
        return try decode(T.self, from: data)
    }

    /// Follows the `Link: rel="next"` header to collect every page.
    private func getAllPages<T: Decodable>(_ path: String, query: [URLQueryItem]) async throws -> [T] {
        var page = 1
        var all: [T] = []
        while true {
            var q = query
            q.append(URLQueryItem(name: "per_page", value: "100"))
            q.append(URLQueryItem(name: "page", value: String(page)))
            let url = GitHubEndpoint.rest(path, query: q)
            let (data, http) = try await send(method: "GET", url: url,
                                              accept: "application/vnd.github+json",
                                              cacheKey: "GET \(url.absoluteString)")
            let items = try decode([T].self, from: data)
            all.append(contentsOf: items)
            guard hasNextPage(http), !items.isEmpty, page < 20 else { break }
            page += 1
        }
        return all
    }

    // MARK: - Public API

    func currentUser() async throws -> GitHubUser {
        try await get("user")
    }

    func organizations() async throws -> [Organization] {
        try await getAllPages("user/orgs", query: [])
    }

    /// Every repo the user can access (owned, collaborator, and org member repos).
    func discoverRepositories() async throws -> [Repository] {
        try await getAllPages("user/repos", query: [
            URLQueryItem(name: "affiliation", value: "owner,collaborator,organization_member"),
            URLQueryItem(name: "sort", value: "pushed"),
        ])
    }

    /// GitHub Actions runs for a repo (recent first). Caller filters running vs. last-24h.
    func workflowRuns(owner: String, repo: String, perPage: Int = 50) async throws -> [WorkflowRun] {
        let resp: WorkflowRunsResponse = try await get(
            "repos/\(owner)/\(repo)/actions/runs",
            query: [URLQueryItem(name: "per_page", value: String(perPage))]
        )
        return resp.workflowRuns
    }

    /// Unread notifications (includes mentions).
    func notifications() async throws -> [GitHubNotification] {
        try await get("notifications", query: [URLQueryItem(name: "all", value: "false")])
    }

    /// Authoritative rate-limit snapshot. This endpoint does **not** consume quota.
    func fetchRateLimit() async throws -> RateLimitInfo {
        let resp: RateLimitResponse = try await get("rate_limit", cache: false)
        let info = RateLimitInfo(
            coreRemaining: resp.resources.core.remaining,
            coreLimit: resp.resources.core.limit,
            coreReset: resp.resources.core.resetDate,
            searchRemaining: resp.resources.search.remaining,
            searchLimit: resp.resources.search.limit,
            searchReset: resp.resources.search.resetDate
        )
        rateLimit = info
        return info
    }

    // MARK: - GraphQL

    /// PRs that concern the current user, deduplicated across roles, each with CI status.
    func pullRequestsConcerningMe() async throws -> [PRItem] {
        let variables: [String: Any] = [
            "reviewer": "is:open is:pr archived:false review-requested:@me",
            "assignee": "is:open is:pr archived:false assignee:@me",
            "author": "is:open is:pr archived:false author:@me",
        ]
        let data: GraphQL.ConcernsData = try await graphQL(query: GraphQL.concernsQuery, variables: variables)

        var byID: [Int: PRItem] = [:]
        func merge(_ nodes: [GraphQL.PRNode], role: PRRole) {
            for node in nodes {
                guard let item = node.toPRItem(role: role) else { continue }
                if var existing = byID[item.id] {
                    existing.roles.insert(role)
                    byID[item.id] = existing
                } else {
                    byID[item.id] = item
                }
            }
        }
        merge(data.reviewer.nodes, role: .reviewer)
        merge(data.assignee.nodes, role: .assignee)
        merge(data.author.nodes, role: .author)
        return byID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Open PRs for one repo, each with CI status (single GraphQL call).
    func openPullRequests(owner: String, repo: String) async throws -> [PRItem] {
        let variables: [String: Any] = ["owner": owner, "name": repo]
        let data: GraphQL.RepoPRData = try await graphQL(query: GraphQL.repoPRQuery, variables: variables)
        return (data.repository?.pullRequests.nodes ?? [])
            .compactMap { $0.toPRItem(role: nil) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    private func graphQL<T: Decodable>(query: String, variables: [String: Any]) async throws -> T {
        let payload: [String: Any] = ["query": query, "variables": variables]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let (data, _) = try await send(method: "POST", url: GitHubEndpoint.graphQL,
                                       accept: "application/json", body: body)
        let envelope = try decode(GraphQL.Response<T>.self, from: data)
        if let errors = envelope.errors, !errors.isEmpty {
            throw APIError.http(status: 200, message: errors.map(\.message).joined(separator: "; "))
        }
        guard let payload = envelope.data else { throw APIError.decoding("Empty GraphQL data.") }
        return payload
    }

    // MARK: - Rate limit header parsing

    private func updateRateLimit(from http: HTTPURLResponse) {
        guard
            let remainingStr = http.value(forHTTPHeaderField: "X-RateLimit-Remaining"),
            let limitStr = http.value(forHTTPHeaderField: "X-RateLimit-Limit"),
            let remaining = Int(remainingStr), let limit = Int(limitStr)
        else { return }
        let reset = resetDate(from: http) ?? rateLimit.coreReset
        let resource = http.value(forHTTPHeaderField: "X-RateLimit-Resource") ?? "core"

        var info = rateLimit
        if info.coreLimit < 0 { info = RateLimitInfo(coreRemaining: remaining, coreLimit: limit, coreReset: reset, searchRemaining: remaining, searchLimit: limit, searchReset: reset) }
        switch resource {
        case "search":
            info.searchRemaining = remaining; info.searchLimit = limit; info.searchReset = reset
        case "core":
            info.coreRemaining = remaining; info.coreLimit = limit; info.coreReset = reset
        default:
            break   // graphql / other buckets not shown in the panel
        }
        rateLimit = info
    }

    private func resetDate(from http: HTTPURLResponse) -> Date? {
        guard let s = http.value(forHTTPHeaderField: "X-RateLimit-Reset"), let epoch = TimeInterval(s) else { return nil }
        return Date(timeIntervalSince1970: epoch)
    }

    private func hasNextPage(_ http: HTTPURLResponse) -> Bool {
        guard let link = http.value(forHTTPHeaderField: "Link") else { return false }
        return link.contains("rel=\"next\"")
    }
}
