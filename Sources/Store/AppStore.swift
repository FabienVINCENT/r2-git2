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
        case awaitingAuthorization
        case signedIn
    }

    // MARK: - Dependencies

    private let keychain = KeychainStore()
    private let cache = ETagCache()
    private let deviceFlow = DeviceFlowAuth()
    let settings: AppSettings
    private let notifications: NotificationManager
    private var client: GitHubClient
    private static let log = Logger(subsystem: "fr.fabien-vincent.r2-git2", category: "store")

    // MARK: - Auth state

    private(set) var authPhase: AuthPhase = .checking
    private(set) var currentUser: GitHubUser?
    private(set) var deviceCode: DeviceFlowAuth.DeviceCode?
    private(set) var deviceFlowStatus: String?
    private var loginTask: Task<Void, Never>?

    // MARK: - Data

    private(set) var concerningPRs: [PRItem] = []
    private(set) var followedOpenPRs: [PRItem] = []
    private(set) var runningRuns: [RunItem] = []
    private(set) var recentRuns: [RunItem] = []
    private(set) var mentions: [NotificationItem] = []
    private(set) var discoveredRepos: [Repository] = []

    // MARK: - Status

    private(set) var isRefreshing = false
    private(set) var isDiscoveringRepos = false
    private(set) var lastUpdated: Date?
    private(set) var lastError: String?
    private(set) var rateLimit: RateLimitInfo = .unknown

    private var pollingTask: Task<Void, Never>?

    // MARK: - Derived (badge)

    /// Number of PRs where I'm requested as reviewer — drives the menu-bar count.
    var reviewCount: Int { concerningPRs.filter { $0.roles.contains(.reviewer) }.count }

    /// Whether any followed repo had a run fail in the recent window — drives the red dot.
    var hasRecentFailure: Bool { recentRuns.contains { $0.didFail } }

    var followedRepos: [Repository] {
        discoveredRepos.filter { settings.followedRepoIDs.contains($0.id) }
    }

    // MARK: - Init

    init() {
        let token = keychain.read()
        self.settings = AppSettings()
        self.notifications = NotificationManager()
        self.client = GitHubClient(token: token, cache: cache)
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

    // MARK: - Device Flow sign-in

    func startSignIn() {
        guard Config.isClientIDConfigured else {
            lastError = APIError.notConfigured.localizedDescription
            return
        }
        loginTask?.cancel()
        loginTask = Task { await runDeviceFlow() }
    }

    func cancelSignIn() {
        loginTask?.cancel()
        loginTask = nil
        deviceCode = nil
        deviceFlowStatus = nil
        authPhase = .signedOut
    }

    private func runDeviceFlow() async {
        do {
            lastError = nil
            let code = try await deviceFlow.requestCode()
            deviceCode = code
            deviceFlowStatus = DeviceFlowError.authorizationPending.errorDescription
            authPhase = .awaitingAuthorization

            var interval = UInt64(max(code.interval, 5))
            let deadline = Date().addingTimeInterval(TimeInterval(code.expiresIn))

            while !Task.isCancelled {
                try await Task.sleep(nanoseconds: interval * 1_000_000_000)
                if Date() > deadline { deviceFlowStatus = DeviceFlowError.expiredToken.errorDescription; break }
                do {
                    let token = try await deviceFlow.pollForToken(deviceCode: code.deviceCode)
                    try keychain.save(token: token)
                    await client.setToken(token)
                    deviceCode = nil
                    deviceFlowStatus = nil
                    authPhase = .signedIn
                    await afterSignIn()
                    return
                } catch APIError.deviceFlow(.authorizationPending) {
                    continue
                } catch APIError.deviceFlow(.slowDown) {
                    interval += 5
                } catch APIError.deviceFlow(.expiredToken) {
                    deviceFlowStatus = DeviceFlowError.expiredToken.errorDescription
                    break
                } catch APIError.deviceFlow(.accessDenied) {
                    deviceFlowStatus = DeviceFlowError.accessDenied.errorDescription
                    break
                }
            }
        } catch {
            lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            authPhase = .signedOut
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
        loginTask?.cancel(); loginTask = nil
        try? keychain.delete()
        Task { await cache.clear(); await client.setToken(nil) }
        notifications.reset()
        currentUser = nil
        concerningPRs = []; followedOpenPRs = []
        runningRuns = []; recentRuns = []
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

    // MARK: - Refresh

    func refresh() async {
        guard authPhase == .signedIn, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        lastError = nil

        do {
            // Fetch the independent pieces concurrently.
            async let concerning = client.pullRequestsConcerningMe()
            async let notifs = client.notifications()
            let repos = followedRepos

            let concerningResult = try await concerning
            let notifsResult = try await notifs

            // Per-repo PRs + runs (bounded fan-out over the user's followed set).
            var openPRs: [PRItem] = []
            var running: [RunItem] = []
            var recent: [RunItem] = []
            let cutoff = Date().addingTimeInterval(-Config.recentRunsWindow)

            try await withThrowingTaskGroup(of: RepoData.self) { group in
                for repo in repos {
                    group.addTask { [client] in
                        async let prs = client.openPullRequests(owner: repo.ownerLogin, repo: repo.name)
                        async let runs = client.workflowRuns(owner: repo.ownerLogin, repo: repo.name)
                        let mappedRuns = try await runs.map { Self.mapRun($0, repoFullName: repo.fullName) }
                        return RepoData(prs: try await prs, runs: mappedRuns)
                    }
                }
                for try await data in group {
                    openPRs.append(contentsOf: data.prs)
                    for item in data.runs {
                        if item.isRunning { running.append(item) }
                        else if item.startedAt >= cutoff { recent.append(item) }
                    }
                }
            }

            concerningPRs = concerningResult
            followedOpenPRs = openPRs.sorted { $0.updatedAt > $1.updatedAt }
            runningRuns = running.sorted { $0.startedAt > $1.startedAt }
            recentRuns = recent.sorted { $0.startedAt > $1.startedAt }
            mentions = notifsResult.map(Self.mapNotification).sorted { $0.updatedAt > $1.updatedAt }
            if let info = try? await client.fetchRateLimit() {
                rateLimit = info
            } else {
                rateLimit = await client.rateLimit
            }
            lastUpdated = Date()

            notifications.process(concerningPRs: concerningPRs,
                                  mentions: mentions,
                                  failedRuns: recentRuns.filter { $0.didFail })
        } catch {
            if !handleAuthError(error) {
                lastError = (error as? APIError)?.localizedDescription ?? error.localizedDescription
            }
        }
    }

    private struct RepoData { let prs: [PRItem]; let runs: [RunItem] }

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
