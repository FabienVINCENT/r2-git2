import XCTest
// ETagCache is compiled directly into this test module (see project.yml), so no import needed.

final class ETagCacheTests: XCTestCase {

    private func makeCache() -> ETagCache {
        // Unique filename per test run avoids clobbering the app's real cache.
        ETagCache(filename: "test-etag-\(UUID().uuidString).json")
    }

    func testStoreAndRetrieveETag() async {
        let cache = makeCache()
        let key = "GET https://api.github.com/user"
        await cache.update(key: key, etag: "\"abc123\"", data: Data("hello".utf8))

        let etag = await cache.etag(forKey: key)
        let data = await cache.data(forKey: key)

        XCTAssertEqual(etag, "\"abc123\"")
        XCTAssertEqual(data.flatMap { String(data: $0, encoding: .utf8) }, "hello")
        await cache.clear()
    }

    func testMissingETagIsNotStored() async {
        let cache = makeCache()
        let key = "GET https://api.github.com/repos"
        await cache.update(key: key, etag: nil, data: Data("x".utf8))
        let etag = await cache.etag(forKey: key)
        XCTAssertNil(etag)
        await cache.clear()
    }

    func testClearRemovesEverything() async {
        let cache = makeCache()
        await cache.update(key: "k", etag: "\"e\"", data: Data("v".utf8))
        await cache.clear()
        let etag = await cache.etag(forKey: "k")
        XCTAssertNil(etag)
    }
}
