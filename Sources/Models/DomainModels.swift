import Foundation

/// CI / checks roll-up state for a PR, in UI terms.
enum CIStatus: String, Sendable, Codable {
    case passing, failing, pending, none

    /// Maps a GitHub `statusCheckRollup.state` or combined-status string.
    static func from(rollupState: String?) -> CIStatus {
        switch rollupState?.uppercased() {
        case "SUCCESS", "SUCCESS ": return .passing
        case "FAILURE", "ERROR": return .failing
        case "PENDING", "EXPECTED": return .pending
        default: return .none
        }
    }

    /// Rank used by the "CI status" sort: what needs attention floats up, green sinks.
    var attentionRank: Int {
        switch self {
        case .failing: return 0
        case .pending: return 1
        case .none: return 2
        case .passing: return 3
        }
    }
}

/// GitHub's overall `reviewDecision` roll-up for a PR.
enum ReviewDecision: String, Sendable, Codable {
    case approved, changesRequested, reviewRequired, none

    static func from(_ raw: String?) -> ReviewDecision {
        switch raw?.uppercased() {
        case "APPROVED": return .approved
        case "CHANGES_REQUESTED": return .changesRequested
        case "REVIEW_REQUIRED": return .reviewRequired
        default: return .none
        }
    }
}

/// State of a submitted review. Only opinion-bearing states are kept — PENDING and DISMISSED
/// reviews are dropped at mapping time.
enum PRReviewState: String, Sendable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case commented = "COMMENTED"

    var notificationHeadline: String {
        switch self {
        case .approved: return "✅ PR approved"
        case .changesRequested: return "🔁 Changes requested"
        case .commented: return "💬 New review comment"
        }
    }
}

/// The latest submitted review from one reviewer (GraphQL `latestReviews`).
struct PRReview: Sendable, Hashable, Codable {
    let authorLogin: String
    let state: PRReviewState
    let submittedAt: Date
}

/// Why a PR concerns the current user. A PR may have several roles at once.
enum PRRole: String, Sendable, Codable, CaseIterable {
    case reviewer   // review-requested:@me
    case assignee   // assignee:@me
    case author     // author:@me

    var label: String {
        switch self {
        case .reviewer: return "Review requested"
        case .assignee: return "Assigned"
        case .author: return "Author"
        }
    }
    var shortLabel: String {
        switch self {
        case .reviewer: return "reviewer"
        case .assignee: return "assignee"
        case .author: return "author"
        }
    }
}

/// A pull request as shown in the popover.
struct PRItem: Identifiable, Sendable, Hashable {
    let id: Int
    let number: Int
    let title: String
    let repositoryFullName: String
    let url: URL
    let authorLogin: String?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    var roles: Set<PRRole>
    var ci: CIStatus
    var reviewDecision: ReviewDecision = .none
    var latestReviews: [PRReview] = []

    /// Whole days since the PR was opened — the "waiting X days" staleness signal.
    var waitingDays: Int { max(0, Int(Date().timeIntervalSince(createdAt) / 86_400)) }

    /// Bot-authored PR (dependabot, renovate, …). Used to deprioritize/hide automated PRs.
    var isBot: Bool {
        guard let a = authorLogin?.lowercased() else { return false }
        if a.hasSuffix("[bot]") { return true }
        return ["dependabot", "renovate", "github-actions", "snyk-bot",
                "codecov", "imgbot", "greenkeeper", "mergify"].contains(a)
    }

    static func == (l: PRItem, r: PRItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// User-selectable ordering for the PR lists.
enum PRSortOrder: String, Sendable, Codable, CaseIterable {
    case activity   // most recently updated first (default)
    case ci         // failing → pending → no status → passing
    case age        // oldest (stalest) first

    var label: String {
        switch self {
        case .activity: return "Recent activity"
        case .ci: return "CI status"
        case .age: return "Oldest first"
        }
    }
}

extension Array where Element == PRItem {
    /// Applies the chosen order. Bot PRs always sink to the bottom, whatever the order.
    func sortedForDisplay(by order: PRSortOrder) -> [PRItem] {
        sorted { a, b in
            if a.isBot != b.isBot { return !a.isBot }
            switch order {
            case .activity:
                return a.updatedAt > b.updatedAt
            case .ci:
                if a.ci.attentionRank != b.ci.attentionRank { return a.ci.attentionRank < b.ci.attentionRank }
                return a.updatedAt > b.updatedAt
            case .age:
                if a.createdAt != b.createdAt { return a.createdAt < b.createdAt }
                return a.updatedAt > b.updatedAt
            }
        }
    }
}

/// A GitHub Actions run as shown in the popover.
struct RunItem: Identifiable, Sendable, Hashable {
    let id: Int
    let workflowName: String
    let branch: String
    let repositoryFullName: String
    let url: URL
    let status: String
    let conclusion: String?
    let startedAt: Date
    let updatedAt: Date

    /// True while queued or in progress.
    var isRunning: Bool { status == "in_progress" || status == "queued" || status == "requested" || status == "waiting" }
    var didFail: Bool { conclusion == "failure" || conclusion == "timed_out" || conclusion == "startup_failure" }

    /// Elapsed time (running → until updatedAt).
    var duration: TimeInterval { max(0, updatedAt.timeIntervalSince(startedAt)) }

    static func == (l: RunItem, r: RunItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// A notification/mention as shown in the popover.
struct NotificationItem: Identifiable, Sendable, Hashable {
    let id: String
    let title: String
    let reason: String
    let repositoryFullName: String
    let url: URL
    let updatedAt: Date
    let type: String

    var isMention: Bool { reason == "mention" || reason == "team_mention" }

    /// Heuristic: dependency-bot notifications (dependabot/renovate) recognized from the subject
    /// title, since the notifications payload carries no author. Used by the "hide bots" toggle.
    var isBot: Bool {
        let t = title.lowercased()
        return t.hasPrefix("bump ")
            || t.contains("build(deps")
            || t.contains("chore(deps")
            || t.hasPrefix("update dependency ")
    }

    static func == (l: NotificationItem, r: NotificationItem) -> Bool { l.id == r.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

/// Snapshot of REST rate-limit buckets, for the debug panel in Settings.
struct RateLimitInfo: Sendable, Equatable {
    var coreRemaining: Int
    var coreLimit: Int
    var coreReset: Date
    var searchRemaining: Int
    var searchLimit: Int
    var searchReset: Date

    static let unknown = RateLimitInfo(coreRemaining: -1, coreLimit: -1, coreReset: .distantPast,
                                       searchRemaining: -1, searchLimit: -1, searchReset: .distantPast)
    var isKnown: Bool { coreLimit >= 0 }
}
