import SwiftUI

/// The two PR groups: PRs that concern me (any repo), and open PRs on followed repos.
struct PullRequestSection: View {
    let concerning: [PRItem]
    let followedOpen: [PRItem]
    let hasFollowedRepos: Bool

    var body: some View {
        CollapsibleSection(
            title: "PRs for me",
            systemImage: "person.crop.circle.badge.checkmark",
            count: concerning.count,
            accent: Theme.accent,
            emptyText: "No PRs need your attention 🎉"
        ) {
            ForEach(concerning) { pr in row(for: pr, showAuthor: false) }
        }

        Divider().overlay(Theme.separator)

        CollapsibleSection(
            title: "Open PRs (followed)",
            systemImage: "arrow.triangle.pull",
            count: followedOpen.count,
            accent: Theme.accent,
            emptyText: hasFollowedRepos ? "No open PRs" : "Follow repos in Settings to see their PRs"
        ) {
            ForEach(followedOpen) { pr in row(for: pr, showAuthor: true) }
        }
    }

    private func row(for pr: PRItem, showAuthor: Bool) -> some View {
        var badges: [RowBadge] = pr.roles.sorted { $0.rawValue < $1.rawValue }.map {
            RowBadge(text: $0.shortLabel, color: roleColor($0))
        }
        if pr.isDraft { badges.append(RowBadge(text: "draft", color: Theme.neutral)) }

        var meta = pr.repositoryFullName + " · " + relativeTime(pr.updatedAt)
        if showAuthor, let author = pr.authorLogin { meta = "@\(author) · " + meta }

        return ItemRow(
            symbol: pr.ci.symbol,
            symbolColor: pr.ci.color,
            title: "#\(pr.number) \(pr.title)",
            subtitle: meta,
            badges: badges,
            url: pr.url
        )
    }

    private func roleColor(_ role: PRRole) -> Color {
        switch role {
        case .reviewer: return Theme.accent
        case .assignee: return Theme.pending
        case .author: return Theme.success
        }
    }
}
