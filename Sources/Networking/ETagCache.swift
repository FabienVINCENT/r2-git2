import Foundation

/// Persistent store of `ETag` + last successful response body, keyed by request signature.
///
/// GitHub honors `If-None-Match`: a matching ETag returns **304 Not Modified**, which does not
/// count against the primary rate limit. We keep the last 200 response so callers can decode
/// the cached body on a 304. Backed by a JSON file in Application Support.
actor ETagCache {

    struct Entry: Codable {
        var etag: String
        var data: Data
        var storedAt: Date
    }

    private var store: [String: Entry] = [:]
    private let fileURL: URL
    private var flushTask: Task<Void, Never>?

    init(filename: String = "etag-cache.json") {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil, create: true))
            ?? URL.temporaryDirectory
        let dir = base.appendingPathComponent("r2-git2", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
        load()
    }

    func etag(forKey key: String) -> String? { store[key]?.etag }
    func data(forKey key: String) -> Data? { store[key]?.data }

    /// Records a fresh 200 response.
    func update(key: String, etag: String?, data: Data) {
        guard let etag, !etag.isEmpty else { return }
        store[key] = Entry(etag: etag, data: data, storedAt: Date())
        scheduleFlush()
    }

    /// Wipes everything (used on sign-out so a new account never sees stale bodies).
    func clear() {
        store.removeAll()
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) else { return }
        store = decoded
    }

    /// Debounced write so a burst of updates during a refresh cycle results in one disk write.
    private func scheduleFlush() {
        flushTask?.cancel()
        flushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            await self?.flush()
        }
    }

    private func flush() {
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
