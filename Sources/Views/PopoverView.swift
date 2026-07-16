import SwiftUI
import AppKit

/// Root of the menu-bar popover. Routes between the login screen and the data dashboard.
struct PopoverView: View {
    @Bindable var store: AppStore
    @ObservedObject var updater: UpdaterViewModel
    @Environment(\.openSettings) private var openSettings

    /// Measured height of the scrollable content, so the popover is exactly as tall as needed
    /// (and only scrolls once it would exceed `popoverMaxHeight`).
    @State private var contentHeight: CGFloat = 320
    @State private var filterText = ""
    @State private var hideBots = false

    var body: some View {
        Group {
            switch store.authPhase {
            case .checking:
                loading
            case .signedOut:
                LoginView(store: store)
            case .signedIn:
                dashboard
            }
        }
        .frame(width: Theme.popoverWidth)
        .background(VisualEffectBackground())
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
            filterBar
            Divider().overlay(Theme.separator)

            if let error = store.lastError {
                errorBanner(error)
            }

            ScrollView {
                VStack(spacing: 0) {
                    let visible = visibleSections            // empty sections are omitted entirely
                    if visible.isEmpty {
                        emptyState
                    } else {
                        ForEach(visible.indices, id: \.self) { i in
                            if i > 0 { Divider().overlay(Theme.separator) }
                            visible[i].view
                        }
                    }
                }
                .background(GeometryReader { proxy in
                    Color.clear.preference(key: ContentHeightKey.self, value: proxy.size.height)
                })
            }
            // As tall as the content, capped so a long list scrolls instead of overflowing screen.
            .frame(height: min(contentHeight, Theme.popoverMaxHeight))
            .onPreferenceChange(ContentHeightKey.self) { contentHeight = $0 }

            Divider().overlay(Theme.separator)
            footer
        }
    }

    // MARK: - Filter

    private var filterBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            TextField("Filter by title, repo, branch…", text: $filterText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textPrimary)
            if !filterText.isEmpty {
                Button { filterText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            sortMenu

            Button { hideBots.toggle() } label: {
                Image(systemName: hideBots ? "person.fill.xmark" : "person.2")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(hideBots ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .help(hideBots ? "Show bot items (dependabot, …)" : "Hide bot PRs & notifications (dependabot, …)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    /// Sort selector for the PR lists. Tinted when a non-default order is active.
    private var sortMenu: some View {
        Menu {
            Picker("Sort PRs by", selection: Binding(
                get: { store.settings.prSortOrder },
                set: { store.settings.prSortOrder = $0 }
            )) {
                ForEach(PRSortOrder.allCases, id: \.self) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(store.settings.prSortOrder == .activity ? Theme.textTertiary : Theme.accent)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort PRs: \(store.settings.prSortOrder.label)")
    }

    private var query: String { filterText.trimmingCharacters(in: .whitespaces) }

    private func filterPRs(_ prs: [PRItem]) -> [PRItem] {
        var result = prs
        if hideBots { result = result.filter { !$0.isBot } }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.repositoryFullName.localizedCaseInsensitiveContains(query)
            || ($0.authorLogin?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private func filterRuns(_ runs: [RunItem]) -> [RunItem] {
        guard !query.isEmpty else { return runs }
        return runs.filter {
            $0.workflowName.localizedCaseInsensitiveContains(query)
            || $0.branch.localizedCaseInsensitiveContains(query)
            || $0.repositoryFullName.localizedCaseInsensitiveContains(query)
        }
    }

    private func filterNotifs(_ items: [NotificationItem]) -> [NotificationItem] {
        var result = items
        if hideBots { result = result.filter { !$0.isBot } }
        guard !query.isEmpty else { return result }
        return result.filter {
            $0.title.localizedCaseInsensitiveContains(query)
            || $0.repositoryFullName.localizedCaseInsensitiveContains(query)
        }
    }

    /// Opens Settings and forces it frontmost. Needed because this is an accessory (menu-bar)
    /// app: without activating, the Settings window can slip behind other apps' windows and never
    /// come back.
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            let win = NSApp.windows.first { w in
                (w.identifier?.rawValue.localizedCaseInsensitiveContains("settings") ?? false)
                || w.title.localizedCaseInsensitiveContains("settings")
                || w.title.localizedCaseInsensitiveContains("réglages")
            }
            win?.makeKeyAndOrderFront(nil)
            win?.orderFrontRegardless()
        }
    }

    // MARK: - Sections (only non-empty ones are shown)

    private struct SectionSpec: Identifiable { let id: String; let view: AnyView }

    /// Builds each section but keeps only the ones that have at least one row after filtering.
    private var visibleSections: [SectionSpec] {
        let order = store.settings.prSortOrder
        let running = filterRuns(store.runningRuns)
        let failures = filterRuns(store.recentFailures)
        let concerning = filterPRs(store.concerningPRs).sortedForDisplay(by: order)
        let followed = filterPRs(store.followedOpenPRs).sortedForDisplay(by: order)
        let notifs = filterNotifs(store.mentions).sorted { ($0.isMention ? 0 : 1) < ($1.isMention ? 0 : 1) }

        var specs: [SectionSpec] = []

        if !running.isEmpty {
            specs.append(.init(id: "running", view: AnyView(
                CollapsibleSection(title: "Actions running", systemImage: "bolt.horizontal.circle",
                                   count: running.count, accent: Theme.pending) {
                    ForEach(running) { runRow($0, showDuration: false) }
                })))
        }
        if !failures.isEmpty {
            specs.append(.init(id: "failures", view: AnyView(
                CollapsibleSection(title: "Recent failures", systemImage: "xmark.octagon",
                                   count: failures.count, accent: Theme.failure) {
                    ForEach(failures) { runRow($0, showDuration: true) }
                })))
        }
        if !concerning.isEmpty {
            specs.append(.init(id: "concerning", view: AnyView(
                CollapsibleSection(title: "PRs for me", systemImage: "person.crop.circle.badge.checkmark",
                                   count: concerning.count, accent: Theme.accent) {
                    ForEach(concerning) { prRow($0, showAuthor: false) }
                })))
        }
        if !followed.isEmpty {
            // Preserve the global bot-last / recency order within each repo group.
            let grouped = Dictionary(grouping: followed, by: { $0.repositoryFullName })
            let repoOrder = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            specs.append(.init(id: "followed", view: AnyView(
                CollapsibleSection(title: "Open PRs (followed)", systemImage: "arrow.triangle.pull",
                                   count: followed.count, accent: Theme.accent) {
                    ForEach(repoOrder, id: \.self) { repo in
                        repoSubheader(repo, count: grouped[repo]!.count)
                        ForEach(grouped[repo]!) { prRow($0, showAuthor: true, showRepo: false) }
                    }
                })))
        }
        if !notifs.isEmpty {
            specs.append(.init(id: "notifs", view: AnyView(
                CollapsibleSection(title: "Mentions & notifications", systemImage: "at.circle",
                                   count: notifs.count, accent: Theme.failure) {
                    ForEach(notifs) { notifRow($0) }
                })))
        }
        return specs
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 26)).foregroundStyle(Theme.success)
            Text(query.isEmpty && !hideBots ? "All clear ✨" : "Nothing matches your filter")
                .font(.system(size: 12.5, weight: .medium)).foregroundStyle(Theme.textPrimary)
            if store.followedRepos.isEmpty {
                Text("Follow repos in Settings to track their PRs and Actions.")
                    .font(.system(size: 10.5)).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20).padding(.vertical, 34)
    }

    // MARK: - Row builders

    private func prRow(_ pr: PRItem, showAuthor: Bool, showRepo: Bool = true) -> some View {
        var badges: [RowBadge] = pr.roles.sorted { $0.rawValue < $1.rawValue }.map {
            RowBadge(text: $0.shortLabel, color: roleColor($0))
        }
        switch pr.reviewDecision {
        case .approved: badges.append(RowBadge(text: "approved", color: Theme.success))
        case .changesRequested: badges.append(RowBadge(text: "changes requested", color: Theme.failure))
        case .reviewRequired, .none: break
        }
        if pr.isDraft { badges.append(RowBadge(text: "draft", color: Theme.neutral)) }
        if !pr.isDraft, pr.waitingDays >= Config.staleAfterDays {
            badges.append(RowBadge(text: "waiting \(pr.waitingDays)d",
                                   color: pr.waitingDays >= Config.veryStaleAfterDays ? Theme.failure : Theme.pending))
        }
        var parts: [String] = []
        if showAuthor, let author = pr.authorLogin { parts.append("@\(author)") }
        if showRepo { parts.append(pr.repositoryFullName) }
        parts.append(relativeTime(pr.updatedAt))
        return ItemRow(symbol: pr.ci.symbol, symbolColor: pr.ci.color,
                       title: "#\(pr.number) \(pr.title)", subtitle: parts.joined(separator: " · "),
                       badges: badges, url: pr.url)
    }

    /// Lightweight subheader used to group followed PRs by repository.
    private func repoSubheader(_ name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            Text(name).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(Theme.textSecondary)
            Text("\(count)").font(.system(size: 9, weight: .bold))
                .padding(.horizontal, 4).padding(.vertical, 0.5)
                .background(Theme.neutral.opacity(0.18), in: Capsule())
                .foregroundStyle(Theme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 2)
    }

    private func runRow(_ run: RunItem, showDuration: Bool) -> some View {
        var meta = "\(run.branch) · \(run.conclusionLabel)"
        if showDuration { meta += " · \(formatDuration(run.duration))" }
        meta += " · \(relativeTime(showDuration ? run.updatedAt : run.startedAt))"
        return ItemRow(symbol: run.symbol, symbolColor: run.color, title: run.workflowName, subtitle: meta,
                       badges: run.repositoryFullName.isEmpty ? [] : [RowBadge(text: run.repositoryFullName, color: Theme.neutral)],
                       url: run.url, onDismiss: { store.dismissRun(run) })
    }

    private func notifRow(_ item: NotificationItem) -> some View {
        ItemRow(symbol: item.isMention ? "at" : "bell.fill",
                symbolColor: item.isMention ? Theme.failure : Theme.textSecondary,
                title: item.title,
                subtitle: "\(item.repositoryFullName) · \(relativeTime(item.updatedAt))",
                badges: [RowBadge(text: item.reason.replacingOccurrences(of: "_", with: " "),
                                  color: item.isMention ? Theme.failure : Theme.neutral)],
                url: item.url,
                onDismiss: { Task { await store.markNotificationDone(item) } },
                dismissHelp: "Mark as done (remove from GitHub inbox)")
    }

    private func roleColor(_ role: PRRole) -> Color {
        switch role {
        case .reviewer: return Theme.accent
        case .assignee: return Theme.pending
        case .author: return Theme.success
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
            Button {
                openSettingsWindow()
            } label: {
                Image(systemName: "gearshape").font(.system(size: 12))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.textSecondary).help("Settings")

            if updater.isConfigured {
                Button { updater.checkForUpdates() } label: {
                    Image(systemName: "arrow.down.circle").font(.system(size: 12))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.textSecondary)
                .disabled(!updater.canCheckForUpdates).help("Check for updates")
            }

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

/// Reports the popover's scrollable content height so the window can size to fit.
private struct ContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}
