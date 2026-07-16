import Foundation

/// GraphQL queries + response types for PR fetching. Kept separate from `GitHubClient` so the
/// query strings and their matching `Decodable` shapes live side by side.
enum GraphQL {

    // MARK: - Envelope

    struct Response<T: Decodable>: Decodable { let data: T?; let errors: [GQLError]? }
    struct GQLError: Decodable { let message: String }

    // MARK: - Shared PR node

    /// Selection shared by both queries. `commits(last:1)` carries the CI roll-up;
    /// `latestReviews` is the newest submitted review per reviewer (feeds review notifications).
    static let prFields = """
      databaseId
      number
      title
      url
      isDraft
      createdAt
      updatedAt
      reviewDecision
      repository { nameWithOwner }
      author { login }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
      latestReviews(first: 10) { nodes { state submittedAt author { login } } }
    """

    struct PRNode: Decodable {
        let databaseId: Int?
        let number: Int
        let title: String
        let url: URL
        let isDraft: Bool
        let createdAt: Date
        let updatedAt: Date
        let reviewDecision: String?
        let repository: Repo
        let author: Author?
        let commits: Commits
        let latestReviews: Reviews?

        struct Repo: Decodable { let nameWithOwner: String }
        struct Author: Decodable { let login: String }
        struct Commits: Decodable { let nodes: [CommitNode] }
        struct CommitNode: Decodable { let commit: Commit }
        struct Commit: Decodable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable { let state: String }
        struct Reviews: Decodable { let nodes: [ReviewNode] }
        struct ReviewNode: Decodable { let state: String; let submittedAt: Date?; let author: Author? }

        /// Converts to the UI model. `role` is the initial role (nil for followed-repo PRs).
        func toPRItem(role: PRRole?) -> PRItem? {
            guard let id = databaseId else { return nil }
            let rollupState = commits.nodes.first?.commit.statusCheckRollup?.state
            // Keep only submitted, opinion-bearing reviews (PENDING/DISMISSED are noise here).
            let reviews: [PRReview] = (latestReviews?.nodes ?? []).compactMap { node in
                guard let state = PRReviewState(rawValue: node.state),
                      let submittedAt = node.submittedAt,
                      let login = node.author?.login else { return nil }
                return PRReview(authorLogin: login, state: state, submittedAt: submittedAt)
            }
            return PRItem(
                id: id,
                number: number,
                title: title,
                repositoryFullName: repository.nameWithOwner,
                url: url,
                authorLogin: author?.login,
                isDraft: isDraft,
                createdAt: createdAt,
                updatedAt: updatedAt,
                roles: role.map { [$0] } ?? [],
                ci: .from(rollupState: rollupState),
                reviewDecision: .from(reviewDecision),
                latestReviews: reviews.sorted { $0.submittedAt > $1.submittedAt }
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
