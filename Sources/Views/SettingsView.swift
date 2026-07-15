import SwiftUI

/// The Settings window (separate from the popover). Account, followed-repo selection, refresh
/// cadence, launch-at-login, and a debug rate-limit readout.
struct SettingsView: View {
    @Bindable var store: AppStore
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        TabView {
            AccountTab(store: store).tabItem { Label("Account", systemImage: "person.crop.circle") }
            RepositoriesTab(store: store).tabItem { Label("Repositories", systemImage: "folder") }
            PreferencesTab(store: store, updater: updater).tabItem { Label("Preferences", systemImage: "gearshape") }
        }
        .frame(width: 460, height: 460)
    }
}

// MARK: - Account

private struct AccountTab: View {
    @Bindable var store: AppStore

    var body: some View {
        Form {
            Section("GitHub account") {
                if let user = store.currentUser {
                    LabeledContent("Signed in as", value: "@\(user.login)")
                    if let url = user.htmlURL {
                        Button("Open profile") { openInBrowser(url) }
                    }
                } else {
                    Text("Not signed in").foregroundStyle(.secondary)
                }
                Button("Sign out", role: .destructive) { store.signOut() }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

// MARK: - Repositories

private struct RepositoriesTab: View {
    @Bindable var store: AppStore
    @State private var search = ""

    private var filtered: [Repository] {
        guard !search.isEmpty else { return store.discoveredRepos }
        return store.discoveredRepos.filter { $0.fullName.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Followed repositories")
                    .font(.headline)
                Spacer()
                Text("\(store.settings.followedRepoIDs.count) followed")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await store.discoverRepositories() }
                } label: {
                    if store.isDiscoveringRepos { ProgressView().controlSize(.small) }
                    else { Image(systemName: "arrow.clockwise") }
                }
                .help("Re-scan accessible repositories")
                .disabled(store.isDiscoveringRepos)
            }

            Text("Pick which repos to track for open PRs and Actions. Nothing is followed by default.")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Filter repositories…", text: $search)
                .textFieldStyle(.roundedBorder)

            List {
                ForEach(filtered) { repo in
                    Toggle(isOn: Binding(
                        get: { store.settings.isFollowing(repo) },
                        set: { _ in store.settings.toggleFollow(repo) }
                    )) {
                        HStack(spacing: 6) {
                            Image(systemName: repo.isPrivate ? "lock.fill" : "book.closed")
                                .font(.caption2).foregroundStyle(.secondary)
                            Text(repo.fullName).font(.system(size: 12))
                            if repo.archived == true {
                                Text("archived").font(.caption2)
                                    .padding(.horizontal, 4).background(.quaternary, in: Capsule())
                            }
                        }
                    }
                }
                if store.discoveredRepos.isEmpty {
                    Text(store.isDiscoveringRepos ? "Scanning…" : "No repositories found.")
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.bordered)
        }
        .padding()
    }
}

// MARK: - Preferences

private struct PreferencesTab: View {
    @Bindable var store: AppStore
    @ObservedObject var updater: UpdaterViewModel

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Auto-refresh every", selection: Binding(
                    get: { store.settings.refreshInterval },
                    set: { store.settings.refreshInterval = $0; store.restartPolling() }
                )) {
                    ForEach(Config.refreshIntervals, id: \.self) { interval in
                        Text(intervalLabel(interval)).tag(interval)
                    }
                }
            }

            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { store.settings.launchAtLogin },
                    set: { store.settings.launchAtLogin = $0 }
                ))
            }

            Section("Updates") {
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { updater.automaticallyChecksForUpdates },
                    set: { updater.automaticallyChecksForUpdates = $0 }
                ))
                Button("Check for updates now") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }

            Section("Rate limit (debug)") {
                if store.rateLimit.isKnown {
                    LabeledContent("Core", value: "\(store.rateLimit.coreRemaining)/\(store.rateLimit.coreLimit)")
                    LabeledContent("Search", value: "\(store.rateLimit.searchRemaining)/\(store.rateLimit.searchLimit)")
                    LabeledContent("Resets", value: relativeTime(store.rateLimit.coreReset))
                } else {
                    Text("Not yet fetched").foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func intervalLabel(_ seconds: TimeInterval) -> String {
        let m = Int(seconds / 60)
        return m >= 60 ? "\(m / 60) h" : "\(m) min"
    }
}
