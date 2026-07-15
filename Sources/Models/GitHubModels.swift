import Foundation

// MARK: - Primitives

struct GitHubUser: Decodable, Sendable, Identifiable {
    let id: Int
    let login: String
    let avatarURL: URL?
    let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, login
        case avatarURL = "avatar_url"
        case htmlURL = "html_url"
    }
}

struct Organization: Decodable, Sendable, Identifiable {
    let id: Int
    let login: String
    let avatarURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, login
        case avatarURL = "avatar_url"
    }
}

struct Repository: Decodable, Sendable, Identifiable, Hashable {
    let id: Int
    let name: String
    let fullName: String        // "owner/repo"
    let isPrivate: Bool
    let htmlURL: URL?
    let owner: RepoOwner
    let archived: Bool?
    let pushedAt: Date?

    var ownerLogin: String { owner.login }

    enum CodingKeys: String, CodingKey {
        case id, name, owner, archived
        case fullName = "full_name"
        case isPrivate = "private"
        case htmlURL = "html_url"
        case pushedAt = "pushed_at"
    }

    static func == (lhs: Repository, rhs: Repository) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct RepoOwner: Decodable, Sendable {
    let login: String
    let avatarURL: URL?
    enum CodingKeys: String, CodingKey { case login; case avatarURL = "avatar_url" }
}

// MARK: - Search (issues / PRs)

struct SearchResponse<Item: Decodable & Sendable>: Decodable, Sendable {
    let totalCount: Int
    let incompleteResults: Bool
    let items: [Item]
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case incompleteResults = "incomplete_results"
        case items
    }
}

/// A row from the issues Search API. PRs are issues whose `pullRequest` field is present.
struct IssueSearchItem: Decodable, Sendable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let state: String
    let user: GitHubUser?
    let repositoryURL: URL          // https://api.github.com/repos/owner/repo
    let updatedAt: Date
    let createdAt: Date
    let draft: Bool?
    let pullRequest: PullRequestRef?

    /// Derives "owner/repo" from the repository API URL.
    var repositoryFullName: String {
        let comps = repositoryURL.pathComponents
        guard comps.count >= 2 else { return "" }
        return "\(comps[comps.count - 2])/\(comps[comps.count - 1])"
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, user, draft
        case htmlURL = "html_url"
        case repositoryURL = "repository_url"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
        case pullRequest = "pull_request"
    }

    struct PullRequestRef: Decodable, Sendable { let url: URL? }
}

// MARK: - Pull Requests (REST, for followed repos)

struct PullRequest: Decodable, Sendable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: URL
    let state: String
    let draft: Bool?
    let user: GitHubUser?
    let head: Ref
    let base: Ref
    let updatedAt: Date
    let createdAt: Date

    struct Ref: Decodable, Sendable {
        let ref: String
        let sha: String
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, state, draft, user, head, base
        case htmlURL = "html_url"
        case updatedAt = "updated_at"
        case createdAt = "created_at"
    }
}

// MARK: - Combined commit status (CI for followed-repo PRs)

struct CombinedStatus: Decodable, Sendable {
    let state: String               // "success" | "failure" | "pending"
    let totalCount: Int
    enum CodingKeys: String, CodingKey { case state; case totalCount = "total_count" }
}

struct CheckRunsResponse: Decodable, Sendable {
    let totalCount: Int
    let checkRuns: [CheckRun]
    enum CodingKeys: String, CodingKey { case totalCount = "total_count"; case checkRuns = "check_runs" }
}

struct CheckRun: Decodable, Sendable {
    let status: String              // queued | in_progress | completed
    let conclusion: String?         // success | failure | neutral | cancelled | ...
}

// MARK: - GitHub Actions

struct WorkflowRunsResponse: Decodable, Sendable {
    let totalCount: Int
    let workflowRuns: [WorkflowRun]
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count"
        case workflowRuns = "workflow_runs"
    }
}

struct WorkflowRun: Decodable, Sendable, Identifiable {
    let id: Int
    let name: String?
    let headBranch: String?
    let status: String              // queued | in_progress | completed | ...
    let conclusion: String?         // success | failure | cancelled | ...
    let htmlURL: URL
    let event: String?
    let createdAt: Date
    let updatedAt: Date
    let runStartedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, event
        case headBranch = "head_branch"
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case runStartedAt = "run_started_at"
    }
}

// MARK: - Notifications

struct GitHubNotification: Decodable, Sendable, Identifiable {
    let id: String
    let unread: Bool
    let reason: String              // mention | review_requested | assign | ...
    let updatedAt: Date
    let subject: Subject
    let repository: NotifRepo

    struct Subject: Decodable, Sendable {
        let title: String
        let url: URL?               // API URL of the issue/PR (needs mapping to html)
        let type: String            // Issue | PullRequest | ...
    }
    struct NotifRepo: Decodable, Sendable {
        let fullName: String
        let htmlURL: URL?
        enum CodingKeys: String, CodingKey { case fullName = "full_name"; case htmlURL = "html_url" }
    }

    enum CodingKeys: String, CodingKey {
        case id, unread, reason, subject, repository
        case updatedAt = "updated_at"
    }
}

// MARK: - Rate limit

struct RateLimitResponse: Decodable, Sendable {
    let resources: Resources
    struct Resources: Decodable, Sendable {
        let core: Bucket
        let search: Bucket
    }
    struct Bucket: Decodable, Sendable {
        let limit: Int
        let remaining: Int
        let reset: TimeInterval     // epoch seconds
        var resetDate: Date { Date(timeIntervalSince1970: reset) }
    }
}
