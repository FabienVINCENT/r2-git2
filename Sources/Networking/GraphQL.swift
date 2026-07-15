import Foundation

/// GraphQL queries + response types for PR fetching. Kept separate from `GitHubClient` so the
/// query strings and their matching `Decodable` shapes live side by side.
enum GraphQL {

    // MARK: - Envelope

    struct Response<T: Decodable>: Decodable { let data: T?; let errors: [GQLError]? }
    struct GQLError: Decodable { let message: String }

    // MARK: - Shared PR node

    /// Selection shared by both queries. `commits(last:1)` carries the CI roll-up.
    static let prFields = """
      databaseId
      number
      title
      url
      isDraft
      updatedAt
      repository { nameWithOwner }
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    """

    struct PRNode: Decodable {
        let databaseId: Int?
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let updatedAt: Date
        let repository: Repo
        let author: Author?
        let commits: Commits

        struct Repo: Decodable { let nameWithOwner: String }
        struct Author: Decodable { let login: String }
        struct Commits: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String }

        /// Converts to the UI model. `role` is the initial role (nil for followed-repo PRs).
        func toPRItem(role: PRRole?) -> PRItem? {
            guard let id = databaseId else { return nil }
            let rollupState = commits.nodes.first?.commit.statusCheckRollup?.state
            return PRItem(
                id: id,
                number: number,
                title: title,
                repositoryFullName: repository.nameWithOwner,
                url: url,
                authorLogin: author?.login,
                isDraft: isDraft,
                updatedAt: updatedAt,
                roles: role.map { [$0] } ?? [],
                ci: .from(rollupState: rollupState)
            )
        }
    }

    // MARK: - "Concerns me" (3 searches in one round-trip)

    struct ConcernsData: Decodable {
        let reviewer: SearchNodes
        let assignee: SearchNodes
        let author: SearchNodes
        struct SearchNodes: Decodable { let nodes: [PRNode] }
    }

    static let concernsQuery = """
    query($reviewer: String!, $assignee: String!, $author: String!) {
      reviewer: search(query: $reviewer, type: ISSUE, first: 50) { nodes { ... on PullRequest { \(prFields) } } }
      assignee: search(query: $assignee, type: ISSUE, first: 50) { nodes { ... on PullRequest { \(prFields) } } }
      author:   search(query: $author,   type: ISSUE, first: 50) { nodes { ... on PullRequest { \(prFields) } } }
    }
    """

    // MARK: - Open PRs for a followed repo

    struct RepoPRData: Decodable {
        let repository: RepoNode?
        struct RepoNode: Decodable { let pullRequests: Connection }
        struct Connection: Decodable { let nodes: [PRNode] }
    }

    static let repoPRQuery = """
    query($owner: String!, $name: String!) {
      repository(owner: $owner, name: $name) {
        pullRequests(states: OPEN, first: 50, orderBy: { field: UPDATED_AT, direction: DESC }) {
          nodes { \(prFields) }
        }
      }
    }
    """
}
