import Foundation
import Observation
import ServiceManagement
import os

/// User preferences, persisted in `UserDefaults` (never the token — that lives in the Keychain).
@MainActor
@Observable
final class AppSettings {

    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "fr.fabien-vincent.r2-git2", category: "settings")

    private enum Key {
        static let followedRepoIDs = "followedRepoIDs"
        static let refreshInterval = "refreshInterval"
        static let prSortOrder = "prSortOrder"
    }

    /// IDs of repositories the user chose to follow. **Empty by default** — nothing is tracked
    /// until the user ticks a repo in Settings.
    var followedRepoIDs: Set<Int> {
        didSet { defaults.set(Array(followedRepoIDs), forKey: Key.followedRepoIDs) }
    }

    /// Auto-refresh cadence in seconds (default: 10 minutes).
    var refreshInterval: TimeInterval {
        didSet { defaults.set(refreshInterval, forKey: Key.refreshInterval) }
    }

    /// How the PR lists in the popover are ordered.
    var prSortOrder: PRSortOrder {
        didSet { defaults.set(prSortOrder.rawValue, forKey: Key.prSortOrder) }
    }

    /// Whether the app launches at login. Backed by `SMAppService.mainApp`, mirrored for the UI.
    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != oldValue else { return }
            applyLaunchAtLogin(launchAtLogin)
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let ids = (defaults.array(forKey: Key.followedRepoIDs) as? [Int]) ?? []
        self.followedRepoIDs = Set(ids)
        let interval = defaults.double(forKey: Key.refreshInterval)
        self.refreshInterval = interval > 0 ? interval : Config.defaultRefreshInterval
        self.prSortOrder = PRSortOrder(rawValue: defaults.string(forKey: Key.prSortOrder) ?? "") ?? .activity
        self.launchAtLogin = (SMAppService.mainApp.status == .enabled)
    }

    func isFollowing(_ repo: Repository) -> Bool { followedRepoIDs.contains(repo.id) }

    func toggleFollow(_ repo: Repository) {
        if followedRepoIDs.contains(repo.id) { followedRepoIDs.remove(repo.id) }
        else { followedRepoIDs.insert(repo.id) }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } catch {
            Self.log.error("Launch-at-login toggle failed: \(error.localizedDescription)")
            // Revert the mirror to the real state so the UI stays truthful.
            launchAtLogin = (SMAppService.mainApp.status == .enabled)
        }
    }
}
