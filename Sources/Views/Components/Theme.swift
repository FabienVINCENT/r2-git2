import SwiftUI
import AppKit

/// Dark, compact palette for the popover, inspired by the monitoring dashboard reference.
enum Theme {
    static let background = Color(red: 0.09, green: 0.10, blue: 0.13)
    static let surface = Color(red: 0.13, green: 0.14, blue: 0.18)
    static let surfaceHover = Color(red: 0.17, green: 0.18, blue: 0.23)
    static let separator = Color.white.opacity(0.07)

    static let textPrimary = Color.white.opacity(0.92)
    static let textSecondary = Color.white.opacity(0.55)
    static let textTertiary = Color.white.opacity(0.38)

    static let accent = Color(red: 0.35, green: 0.62, blue: 1.0)

    static let success = Color(red: 0.30, green: 0.78, blue: 0.45)
    static let failure = Color(red: 0.92, green: 0.34, blue: 0.34)
    static let pending = Color(red: 0.95, green: 0.77, blue: 0.28)
    static let neutral = Color.white.opacity(0.35)

    static let popoverWidth: CGFloat = 380
    static let popoverMaxHeight: CGFloat = 620
}

/// Opens a GitHub URL in the user's default browser. Every actionable item routes through here.
func openInBrowser(_ url: URL) {
    NSWorkspace.shared.open(url)
}

/// Native translucent (vibrancy) background — the modern macOS "glass" menu look, blurring what's
/// behind the popover — topped with a dark scrim so the panel stays dark and readable even over
/// bright/white windows (the material alone lets too much light through).
struct VisualEffectBackground: View {
    var material: NSVisualEffectView.Material = .hudWindow
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    /// Opacity of the dark layer over the blur. Higher = more opaque panel, fainter glass effect.
    var scrimOpacity: Double = 0.75

    var body: some View {
        VisualEffectRepresentable(material: material, blending: blending)
            .overlay(Theme.background.opacity(scrimOpacity))
    }
}

/// `behindWindow` blending only shows through if the host window itself is non-opaque with a clear
/// background, which the `MenuBarExtra` panel is not by default — so the view fixes that once it's
/// attached to its window.
private struct VisualEffectRepresentable: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blending: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = WindowClearingEffectView()
        view.material = material
        view.blendingMode = blending
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.blendingMode = blending
    }
}

/// An `NSVisualEffectView` that makes its host window transparent so `behindWindow` vibrancy shows.
private final class WindowClearingEffectView: NSVisualEffectView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
    }
}

extension CIStatus {
    var color: Color {
        switch self {
        case .passing: return Theme.success
        case .failing: return Theme.failure
        case .pending: return Theme.pending
        case .none: return Theme.neutral
        }
    }
    var symbol: String {
        switch self {
        case .passing: return "checkmark.circle.fill"
        case .failing: return "xmark.octagon.fill"
        case .pending: return "clock.fill"
        case .none: return "circle.dashed"
        }
    }
}

extension RunItem {
    var color: Color {
        if isRunning { return Theme.pending }
        switch conclusion {
        case "success": return Theme.success
        case "failure", "timed_out", "startup_failure": return Theme.failure
        case "cancelled": return Theme.neutral
        default: return Theme.neutral
        }
    }
    var symbol: String {
        if isRunning { return "circle.dotted" }
        switch conclusion {
        case "success": return "checkmark.circle.fill"
        case "failure", "timed_out", "startup_failure": return "xmark.octagon.fill"
        case "cancelled": return "minus.circle.fill"
        default: return "questionmark.circle"
        }
    }
    var conclusionLabel: String {
        if isRunning { return status == "queued" ? "Queued" : "In progress" }
        return (conclusion ?? status).replacingOccurrences(of: "_", with: " ").capitalized
    }
}

/// Compact relative timestamp: "2 min ago", "3 h ago".
func relativeTime(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .abbreviated
    return f.localizedString(for: date, relativeTo: Date())
}

/// Human duration like "1m 20s".
func formatDuration(_ seconds: TimeInterval) -> String {
    let total = Int(seconds)
    let m = total / 60, s = total % 60
    return m > 0 ? "\(m)m \(s)s" : "\(s)s"
}
