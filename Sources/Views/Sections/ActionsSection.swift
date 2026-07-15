import SwiftUI

/// GitHub Actions: in-progress runs, then runs finished in the last 24 h.
struct ActionsSection: View {
    let running: [RunItem]
    let recent: [RunItem]
    let hasFollowedRepos: Bool

    var body: some View {
        CollapsibleSection(
            title: "Actions running",
            systemImage: "bolt.horizontal.circle",
            count: running.count,
            accent: Theme.pending,
            emptyText: hasFollowedRepos ? "Nothing running" : "Follow repos to see their runs"
        ) {
            ForEach(running) { run in row(for: run, showDuration: false) }
        }

        Divider().overlay(Theme.separator)

        CollapsibleSection(
            title: "Actions (last 24h)",
            systemImage: "clock.arrow.circlepath",
            count: recent.count,
            accent: Theme.accent,
            emptyText: "No recent runs"
        ) {
            ForEach(recent) { run in row(for: run, showDuration: true) }
        }
    }

    private func row(for run: RunItem, showDuration: Bool) -> some View {
        var meta = "\(run.branch) · \(run.conclusionLabel)"
        if showDuration { meta += " · \(formatDuration(run.duration))" }
        meta += " · \(relativeTime(run.startedAt))"

        return ItemRow(
            symbol: run.symbol,
            symbolColor: run.color,
            title: run.workflowName,
            subtitle: meta,
            badges: run.repositoryFullName.isEmpty ? [] : [RowBadge(text: run.repositoryFullName, color: Theme.neutral)],
            url: run.url
        )
    }
}
