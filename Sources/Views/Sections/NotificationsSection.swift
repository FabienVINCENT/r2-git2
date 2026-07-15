import SwiftUI

/// GitHub notifications, with mentions highlighted at the top.
struct NotificationsSection: View {
    let items: [NotificationItem]

    private var mentions: [NotificationItem] { items.filter { $0.isMention } }
    private var others: [NotificationItem] { items.filter { !$0.isMention } }

    var body: some View {
        CollapsibleSection(
            title: "Mentions & notifications",
            systemImage: "at.circle",
            count: items.count,
            accent: Theme.failure,
            emptyText: "No unread notifications"
        ) {
            ForEach(mentions) { row(for: $0, isMention: true) }
            ForEach(others) { row(for: $0, isMention: false) }
        }
    }

    private func row(for item: NotificationItem, isMention: Bool) -> some View {
        ItemRow(
            symbol: isMention ? "at" : "bell.fill",
            symbolColor: isMention ? Theme.failure : Theme.textSecondary,
            title: item.title,
            subtitle: "\(item.repositoryFullName) · \(relativeTime(item.updatedAt))",
            badges: [RowBadge(text: item.reason.replacingOccurrences(of: "_", with: " "),
                              color: isMention ? Theme.failure : Theme.neutral)],
            url: item.url
        )
    }
}
