import SwiftUI

/// Root of the menu-bar popover. Routes between the login screen and the data dashboard.
struct PopoverView: View {
    @Bindable var store: AppStore
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Group {
            switch store.authPhase {
            case .checking:
                loading
            case .signedOut, .awaitingAuthorization:
                LoginView(store: store)
            case .signedIn:
                dashboard
            }
        }
        .frame(width: Theme.popoverWidth)
        .background(Theme.background)
        .task { if store.authPhase == .checking { await store.bootstrap() } }
    }

    // MARK: - Loading

    private var loading: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.small)
            Text("Loading…").font(.system(size: 12)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    // MARK: - Dashboard

    private var dashboard: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.separator)

            if let error = store.lastError {
                errorBanner(error)
            }

            ScrollView {
                VStack(spacing: 0) {
                    PullRequestSection(
                        concerning: store.concerningPRs,
                        followedOpen: store.followedOpenPRs,
                        hasFollowedRepos: !store.followedRepos.isEmpty
                    )
                    Divider().overlay(Theme.separator)
                    ActionsSection(
                        running: store.runningRuns,
                        recent: store.recentRuns,
                        hasFollowedRepos: !store.followedRepos.isEmpty
                    )
                    Divider().overlay(Theme.separator)
                    NotificationsSection(items: store.mentions)
                }
            }
            .frame(maxHeight: Theme.popoverMaxHeight)

            Divider().overlay(Theme.separator)
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            statusDot
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(updatedText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                if store.isRefreshing {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 20, height: 20)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textSecondary)
            .help("Refresh now")
            .disabled(store.isRefreshing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var statusDot: some View {
        Circle()
            .fill(store.hasRecentFailure ? Theme.failure : (store.reviewCount > 0 ? Theme.pending : Theme.success))
            .frame(width: 9, height: 9)
    }

    private var statusTitle: String {
        if store.hasRecentFailure { return "Attention needed" }
        if store.reviewCount > 0 { return "\(store.reviewCount) PR\(store.reviewCount > 1 ? "s" : "") to review" }
        return "All clear"
    }

    private var updatedText: String {
        guard let last = store.lastUpdated else { return store.isRefreshing ? "Refreshing…" : "Not yet updated" }
        return "Updated \(relativeTime(last))"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let user = store.currentUser {
                Text("@\(user.login)").font(.system(size: 10.5)).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            SettingsLink {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary).help("Settings")

            Button { updater.checkForUpdates() } label: {
                Image(systemName: "arrow.down.circle").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
            .disabled(!updater.canCheckForUpdates).help("Check for updates")

            Button { NSApplication.shared.terminate(nil) } label: {
                Image(systemName: "power").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary).help("Quit r2-git2")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.failure)
            Text(message).font(.system(size: 11)).foregroundStyle(Theme.textPrimary).lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Theme.failure.opacity(0.12))
    }
}
