import SwiftUI

/// A small colored pill used to tag a row (e.g. PR role, CI state).
struct RowBadge: Identifiable {
    let id = UUID()
    let text: String
    let color: Color
}

/// One clickable line in the popover: colored status icon · title + meta · trailing chevron.
/// Tapping opens the associated GitHub URL in the browser.
struct ItemRow: View {
    let symbol: String
    let symbolColor: Color
    let title: String
    let subtitle: String
    var badges: [RowBadge] = []
    let url: URL
    /// When set, a "mark handled" button appears on hover that calls this instead of opening.
    var onDismiss: (() -> Void)? = nil
    var dismissHelp: String = "Mark as handled (hide)"

    @State private var hovering = false

    var body: some View {
        Button {
            openInBrowser(url)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(symbolColor)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 6) {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }

                    if !badges.isEmpty {
                        HStack(spacing: 5) {
                            ForEach(badges) { badge in
                                Text(badge.text)
                                    .font(.system(size: 9.5, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(badge.color.opacity(0.18), in: Capsule())
                                    .foregroundStyle(badge.color)
                            }
                        }
                    }
                }

                Spacer(minLength: 4)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help(dismissHelp)
                    .opacity(hovering ? 1 : 0)
                    .padding(.top, 1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(hovering ? Theme.surfaceHover : Color.clear)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
