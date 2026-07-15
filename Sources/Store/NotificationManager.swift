import Foundation
import UserNotifications
import os

/// Fires native macOS notifications for: new PRs requesting my review / assigned to me, new
/// mentions, and newly-failed Actions runs on followed repos. Deduplicated via a persisted set
/// of "seen" keys so a subsequent refresh never re-notifies the same item.
@MainActor
final class NotificationManager {

    private let center = UNUserNotificationCenter.current()
    private let defaults: UserDefaults
    private static let log = Logger(subsystem: "fr.fabien-vincent.r2-git2", category: "notifications")

    private var seen: Set<String>
    private var didSeedBaseline: Bool

    private enum Key {
        static let seen = "notif.seenKeys"
        static let seeded = "notif.didSeedBaseline"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.seen = Set(defaults.stringArray(forKey: Key.seen) ?? [])
        self.didSeedBaseline = defaults.bool(forKey: Key.seeded)
    }

    func requestAuthorization() {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error { Self.log.error("Notification auth error: \(error.localizedDescription)") }
            else { Self.log.info("Notification permission granted: \(granted)") }
        }
    }

    /// Inspect the latest data and notify about anything new. Opening a notification launches
    /// the associated GitHub URL (handled in `AppDelegate`).
    func process(concerningPRs: [PRItem], mentions: [NotificationItem], failedRuns: [RunItem]) {
        var pending: [(id: String, title: String, body: String, url: URL)] = []

        for pr in concerningPRs where pr.roles.contains(.reviewer) || pr.roles.contains(.assignee) {
            let key = "pr:\(pr.id)"
            guard !seen.contains(key) else { continue }
            let role = pr.roles.contains(.reviewer) ? "Review requested" : "Assigned to you"
            pending.append((key, "\(role) · \(pr.repositoryFullName)", "#\(pr.number) \(pr.title)", pr.url))
        }

        for m in mentions where m.isMention {
            let key = "mention:\(m.id)"
            guard !seen.contains(key) else { continue }
            pending.append((key, "Mention · \(m.repositoryFullName)", m.title, m.url))
        }

        for run in failedRuns {
            let key = "run:\(run.id)"
            guard !seen.contains(key) else { continue }
            pending.append((key, "❌ CI failed · \(run.repositoryFullName)", "\(run.workflowName) on \(run.branch)", run.url))
        }

        // First run: record everything as seen without alerting, so we only notify future changes.
        guard didSeedBaseline else {
            pending.forEach { seen.insert($0.id) }
            persist()
            didSeedBaseline = true
            defaults.set(true, forKey: Key.seeded)
            return
        }

        for item in pending {
            deliver(id: item.id, title: item.title, body: item.body, url: item.url)
            seen.insert(item.id)
        }
        pruneIfNeeded()
        persist()
    }

    /// Reset baseline (e.g. on sign-out) so a new account starts clean.
    func reset() {
        seen.removeAll()
        didSeedBaseline = false
        defaults.removeObject(forKey: Key.seen)
        defaults.removeObject(forKey: Key.seeded)
    }

    private func deliver(id: String, title: String, body: String, url: URL) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = ["url": url.absoluteString]   // read by AppDelegate on tap
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        center.add(request)
    }

    /// Keep the seen set from growing unbounded across months of use.
    private func pruneIfNeeded() {
        guard seen.count > 500 else { return }
        seen = Set(seen.suffix(300))
    }

    private func persist() { defaults.set(Array(seen), forKey: Key.seen) }
}
