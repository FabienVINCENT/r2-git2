import SwiftUI

/// A collapsible section with a header (icon · title · count) and disclosure chevron.
/// Empty sections show a subdued placeholder instead of hiding, so the layout stays predictable.
struct CollapsibleSection<Content: View>: View {
    let title: String
    let systemImage: String
    let count: Int
    var accent: Color = Theme.accent
    var emptyText: String = "Nothing here"
    @ViewBuilder let content: () -> Content

    @State private var expanded = true

    var body: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(title.uppercased())
                        .font(.system(size: 10.5, weight: .bold))
                        .foregroundStyle(Theme.textSecondary)
                        .tracking(0.5)
                    if count > 0 {
                        Text("\(count)")
                            .font(.system(size: 9.5, weight: .bold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(accent.opacity(0.2), in: Capsule())
                            .foregroundStyle(accent)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                if count == 0 {
                    HStack {
                        Text(emptyText)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                } else {
                    content()
                        .padding(.bottom, 4)
                }
            }
        }
    }
}
