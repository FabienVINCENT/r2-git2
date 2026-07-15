import SwiftUI

/// The status-bar item content: a git glyph, the review count, and a failure indicator.
///
/// Note: menu-bar images are template-rendered so they adapt to light/dark automatically. A
/// literal colored dot can't survive that, so a failure is surfaced as an alert glyph instead —
/// still unmistakable, and it adapts to the user's menu-bar appearance.
struct MenuBarLabel: View {
    let reviewCount: Int
    let hasFailure: Bool

    private var symbol: String {
        hasFailure ? "exclamationmark.triangle.fill" : "arrow.triangle.branch"
    }

    var body: some View {
        Label(reviewCount > 0 ? "\(reviewCount)" : "", systemImage: symbol)
            .labelStyle(.titleAndIcon)
    }
}
