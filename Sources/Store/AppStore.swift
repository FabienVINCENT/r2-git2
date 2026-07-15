import Foundation
import Observation
import os

/// The single source of truth for the UI. Owns auth, data, polling, and derived badge state.
/// `@MainActor` so SwiftUI observation is always on the main thread; network work is delegated
/// to the actor-isolated `GitHubClient`.
@MainActor
@Observable
final class AppStore {

    // MARK: - Sub-states

    enum AuthPhase: Equatable {
        case checking
        case signedOut
        case signedIn
    }

    // MARK: - Dependencies

    private let keychain = KeychainStore()
    private let cache = ETagCache()
    let settings: AppSettings
    private let notifications: NotificationManager
    private var client: GitHubClient
    private static let log = Logger(subsystem: "fr.fabien-vincent.r2-git2", category: "store")

    // MARK: - Auth state

    private(set) var authPhase: AuthPhase = .checking
    private(set) var currentUser: GitHubUser?

    // MARK: - Data

    private(set) var concerningPRs: [PRItem] = []
    private(set) var followedOpenPRs: [PRItem] = []
    private(set) var runningRuns: [RunItem] = []
    private(set) var recentFailures: [RunItem] = []
    private(set) var mentions: [NotificationItem] = []
    private(set) var discoveredRepos: [Repository] = []

    // MARK: - Status

    private(set) var isRefreshing = false
    private(set) var isDiscoveringRepos = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var rateLimit: RateLimitInfo = .unknown

    private var pollingTask: Task<Void, Never>?
    private var followRefreshTask: Task<Void, Never>?

    // MARK: - Derived (badge)

    /// Number of PRs where I'm requested as reviewer — drives the menu-bar count.
    var reviewCount: Int { concerningPRs.filter { $0.roles.contains(.reviewer) }.count }

    /// Whether any followed repo had a run fail in the recent window — drives the red dot.
    var hasRecentFailure: Bool { !recentFailures.isEmpty }

    var followedRepos: [Repository] {
        discoveredRepos.filter { settings.followedRepoIDs.contains($0.id) }
    }

    // MARK: - Init

    init() {
        let token = keychain.read()
        self.settings = AppSettings()
        self.notifications = NotificationManager()
        self.client = GitHubClient(token: token, cache: cache)
        loadDismissedRuns()
    }

    // MARK: - Dismissed runs

    /// Runs the user has hidden ("handled"), keyed by run id → the `updatedAt` seen at dismissal.
    /// If a run gets newer activity (e.g. it's re-run), it reappears. Persisted so it survives
    /// relaunch.
    private(set) var dismissedRuns: [Int: Date] = [:]
    private let dismissedRunsKey = "dismissedRuns"

    func dismissRun(_ run: RunItem) {
        dismissedRuns[run.id] = run.updatedAt
        pruneDismissedRuns()
        saveDismissedRuns()
        runningRuns.removeAll { $0.id == run.id }
        recentFailures.removeAll { $0.id == run.id }
    }

    /// "Mark as done" a notification: marks it read on GitHub and drops it from the list.
    func markNotificationDone(_ item: NotificationItem) async {
        mentions.removeAll { $0.id == item.id }   // optimistic — feels instant
        do {
            try await client.markNotificationRead(id: item.id)
        } catch {
            if !handleAuthError(error) {
                lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    private func isDismissed(_ run: RunItem) -> Bool {
        if let seenAt = dismissedRuns[run.id] { return run.updatedAt <= seenAt }
        return false
    }

    private func pruneDismissedRuns() {
        // Runs older than the display window are never shown anyway — forget their dismissal.
        let cutoff = Date().addingTimeInterval(-Config.recentFailureWindow * 4)
        dismissedRuns = dismissedRuns.filter { $0.value >= cutoff }
    }

    private func loadDismissedRuns() {
        guard let dict = UserDefaults.standard.dictionary(forKey: dismissedRunsKey) as? [String: Double] else { return }
        dismissedRuns = Dictionary(uniqueKeysWithValues: dict.compactMap { key, value in
            Int(key).map { ($0, Date(timeIntervalSince1970: value)) }
        })
    }

    private func saveDismissedRuns() {
        let dict = Dictionary(uniqueKeysWithValues: dismissedRuns.map { (String($0.key), $0.value.timeIntervalSince1970) })
        UserDefaults.standard.set(dict, forKey: dismissedRunsKey)
    }

    // MARK: - Lifecycle

    /// Called once at launch. Restores a session if a token exists.
    func bootstrap() async {
        notifications.requestAuthorization()
        if keychain.hasToken {
            authPhase = .signedIn
            await afterSignIn()
        } else {
            authPhase = .signedOut
        }
    }

    // MARK: - Personal Access Token sign-in

    private(set) var isValidatingToken = false

    /// Validates a pasted Personal Access Token (`GET /user`) and, on success, stores it in the
    /// Keychain and starts the session. Avoids the OAuth per-org grant screen entirely.
    func signIn(withToken rawToken: String) async {
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }

        isValidatingToken = true
        defer { isValidatingToken = false }
        lastError = nil

        // Point the client at the candidate token, but don't persist until it's proven valid.
        await client.setToken(token)
        do {
            currentUser = try await client.currentUser()
            try keychain.save(token: token)
            authPhase = .signedIn
            await afterSignIn()
        } catch {
            // Revert to whatever token was there before (usually none).
            await client.setToken(keychain.read())
            if let apiError = error as? APIError, apiError.requiresReauth {
                lastError = "Invalid token, or it lacks the required scopes (repo, read:org, notifications)."
            } else {
                lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    /// Shared post-login work: load user, discover repos, start polling, first refresh.
    private func afterSignIn() async {
        do {
            currentUser = try await client.currentUser()
        } catch {
            if handleAuthError(error) { return }
        }
        await discoverRepositories()
        startPolling()
        await refresh()
    }

    // MARK: - Sign out

    func signOut() {
        pollingTask?.cancel(); pollingTask = nil
        try? keychain.delete()
        Task { await cache.clear(); await client.setToken(nil) }
        notifications.reset()
        currentUser = nil
        concerningPRs = []; followedOpenPRs = []
        runningRuns = []; recentFailures = []
        mentions = []; discoveredRepos = []
        lastUpdated = nil; lastError = nil
        rateLimit = .unknown
        authPhase = .signedOut
    }

    // MARK: - Repo discovery

    func discoverRepositories() async {
        guard authPhase == .signedIn else { return }
        isDiscoveringRepos = true
        defer { isDiscoveringRepos = false }
        do {
            let repos = try await client.discoverRepositories()
            discoveredRepos = repos.sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
        } catch {
            _ = handleAuthError(error)
        }
    }

    /// Toggle following a repo and refresh shortly after — debounced so ticking several repos in
    /// a row triggers a single refresh once the user settles.
    func toggleFollow(_ repo: Repository) {
        settings.toggleFollow(repo)
        followRefreshTask?.cancel()
        followRefreshTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    // MARK: - Refresh

    func refresh() async {
        guard authPhase == .signedIn, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        // Each section fetches independently: a hiccup in one (or in a single followed repo)
        // must never blank the others. Only a 401 is fatal — it signs the user out.
        var problem: String?
        func note(_ error: Error) -> Bool {
            if handleAuthError(error) { return true }          // fatal → stop
            problem = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            Self.log.error("Refresh error: \(problem ?? "", privacy: .public)")
            return false
        }

        // "PRs for me" (any repo).
        do { concerningPRs = Self.sortPRs(try await client.pullRequestsConcerningMe()) }
        catch { if note(error) { return } }

        // Notifications / mentions.
        do { mentions = try await client.notifications().map(Self.mapNotification).sorted { $0.updatedAt > $1.updatedAt } }
        catch { if note(error) { return } }

        // Followed repos: PRs + Actions runs, resilient per repo.
        let repos = followedRepos
        let failureCutoff = Date().addingTimeInterval(-Config.recentFailureWindow)
        var openPRs: [PRItem] = []
        var running: [RunItem] = []
        var failures: [RunItem] = []

        await withTaskGroup(of: RepoData?.self) { group in
            for repo in repos {
                group.addTask { [client] in
                    do {
                        async let prs = client.openPullRequests(owner: repo.ownerLogin, repo: repo.name)
                        async let runs = client.workflowRuns(owner: repo.ownerLogin, repo: repo.name)
                        let mappedRuns = try await runs.map { Self.mapRun($0, repoFullName: repo.fullName) }
                        return RepoData(prs: try await prs, runs: mappedRuns)
                    } catch {
                        Self.log.error("Repo \(repo.fullName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
                        return nil
                    }
                }
            }
            for await data in group {
                guard let data else { continue }
                openPRs.append(contentsOf: data.prs)
                for item in data.runs {
                    if isDismissed(item) { continue }         // user marked it handled
                    if item.isRunning { running.append(item) }
                    // Only failures, and only recent ones (by finish time). Successes are hidden.
                    else if item.didFail && item.updatedAt >= failureCutoff { failures.append(item) }
                }
            }
        }

        followedOpenPRs = Self.sortPRs(openPRs)
        runningRuns = running.sorted { $0.startedAt > $1.startedAt }
        recentFailures = failures.sorted { $0.updatedAt > $1.updatedAt }

        if let info = try? await client.fetchRateLimit() { rateLimit = info }
        else { rateLimit = await client.rateLimit }

        lastUpdated = Date()
        lastError = problem   // nil clears any previous error once things recover

        notifications.process(concerningPRs: concerningPRs,
                              mentions: mentions,
                              failedRuns: recentFailures)
    }

    private struct RepoData: Sendable { let prs: [PRItem]; let runs: [RunItem] }

    /// Humans first (most-recently updated on top), bot-authored PRs last — dependabot & friends
    /// are rarely the priority.
    nonisolated private static func sortPRs(_ prs: [PRItem]) -> [PRItem] {
        prs.sorted { a, b in
            if a.isBot != b.isBot { return !a.isBot }
            return a.updatedAt > b.updatedAt
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = await self.settings.refreshInterval
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    /// Restart the polling loop (e.g. after the user changes the interval).
    func restartPolling() { if authPhase == .signedIn { startPolling() } }

    // MARK: - Error routing

    /// Returns true if the error was an auth failure that triggered sign-out.
    @discardableResult
    private func handleAuthError(_ error: Error) -> Bool {
        if let apiError = error as? APIError, apiError.requiresReauth {
            Self.log.notice("Token rejected — signing out for re-auth.")
            signOut()
            lastError = APIError.unauthorized.localizedDescription
            return true
        }
        return false
    }

    // MARK: - Mapping

    nonisolated private static func mapRun(_ run: WorkflowRun, repoFullName: String) -> RunItem {
        RunItem(
            id: run.id,
            workflowName: run.name ?? "Workflow",
            branch: run.headBranch ?? "—",
            repositoryFullName: repoFullName,
            url: run.htmlURL,
            status: run.status,
            conclusion: run.conclusion,
            startedAt: run.runStartedAt ?? run.createdAt,
            updatedAt: run.updatedAt
        )
    }

    nonisolated private static func mapNotification(_ n: GitHubNotification) -> NotificationItem {
        NotificationItem(
            id: n.id,
            title: n.subject.title,
            reason: n.reason,
            repositoryFullName: n.repository.fullName,
            url: htmlURL(for: n),
            updatedAt: n.updatedAt,
            type: n.subject.type
        )
    }

    /// Notifications carry an *API* URL; convert to a browser URL, falling back to the repo page.
    nonisolated private static func htmlURL(for n: GitHubNotification) -> URL {
        guard let api = n.subject.url?.absoluteString else {
            return n.repository.htmlURL ?? Config.apiBaseURL
        }
        let html = api
            .replacingOccurrences(of: "https://api.github.com/repos/", with: "https://github.com/")
            .replacingOccurrences(of: "/pulls/", with: "/pull/")
        return URL(string: html) ?? n.repository.htmlURL ?? Config.apiBaseURL
    }
}
