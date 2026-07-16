import XCTest
// Models under test are compiled into this test module directly (see project.yml).

final class PRSortAndReviewTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private func pr(id: Int, bot: Bool = false, ci: CIStatus = .none,
                    created: TimeInterval, updated: TimeInterval) -> PRItem {
        PRItem(id: id, number: id, title: "PR \(id)", repositoryFullName: "o/r",
               url: URL(string: "https://github.com")!,
               authorLogin: bot ? "dependabot" : "alice", isDraft: false,
               createdAt: Date(timeIntervalSince1970: created),
               updatedAt: Date(timeIntervalSince1970: updated),
               roles: [], ci: ci)
    }

    // MARK: - Sorting

    func testSortByActivityKeepsBotsLast() {
        let items = [pr(id: 1, bot: true, created: 0, updated: 900),
                     pr(id: 2, created: 0, updated: 100),
                     pr(id: 3, created: 0, updated: 500)]
        XCTAssertEqual(items.sortedForDisplay(by: .activity).map(\.id), [3, 2, 1])
    }

    func testSortByCIPutsFailingFirstAndPassingLast() {
        let items = [pr(id: 1, ci: .passing, created: 0, updated: 900),
                     pr(id: 2, ci: .pending, created: 0, updated: 100),
                     pr(id: 3, ci: .failing, created: 0, updated: 500),
                     pr(id: 4, ci: .none, created: 0, updated: 700)]
        XCTAssertEqual(items.sortedForDisplay(by: .ci).map(\.id), [3, 2, 4, 1])
    }

    func testSortByAgePutsOldestFirst() {
        let items = [pr(id: 1, created: 300, updated: 900),
                     pr(id: 2, created: 100, updated: 100),
                     pr(id: 3, created: 200, updated: 500)]
        XCTAssertEqual(items.sortedForDisplay(by: .age).map(\.id), [2, 3, 1])
    }

    // MARK: - Staleness

    func testWaitingDaysCountsWholeDaysSinceCreation() {
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 86_400 - 3_600)
        let item = PRItem(id: 1, number: 1, title: "t", repositoryFullName: "o/r",
                          url: URL(string: "https://github.com")!, authorLogin: nil,
                          isDraft: false, createdAt: fiveDaysAgo, updatedAt: Date(),
                          roles: [], ci: .none)
        XCTAssertEqual(item.waitingDays, 5)
    }

    func testWaitingDaysNeverNegative() {
        let item = PRItem(id: 1, number: 1, title: "t", repositoryFullName: "o/r",
                          url: URL(string: "https://github.com")!, authorLogin: nil,
                          isDraft: false, createdAt: Date().addingTimeInterval(600),
                          updatedAt: Date(), roles: [], ci: .none)
        XCTAssertEqual(item.waitingDays, 0)
    }

    // MARK: - Review decision mapping

    func testReviewDecisionMapping() {
        XCTAssertEqual(ReviewDecision.from("APPROVED"), .approved)
        XCTAssertEqual(ReviewDecision.from("CHANGES_REQUESTED"), .changesRequested)
        XCTAssertEqual(ReviewDecision.from("REVIEW_REQUIRED"), .reviewRequired)
        XCTAssertEqual(ReviewDecision.from(nil), ReviewDecision.none)
    }

    // MARK: - GraphQL node → PRItem

    func testDecodePRNodeMapsReviewsAndDropsUnsubmittedOnes() throws {
        let json = """
        {
          "databaseId": 7,
          "number": 12,
          "title": "Add widget",
          "url": "https://github.com/o/r/pull/12",
          "isDraft": false,
          "createdAt": "2026-07-10T09:00:00Z",
          "updatedAt": "2026-07-15T10:00:00Z",
          "reviewDecision": "APPROVED",
          "repository": { "nameWithOwner": "o/r" },
          "author": { "login": "me" },
          "commits": { "nodes": [ { "commit": { "statusCheckRollup": { "state": "SUCCESS" } } } ] },
          "latestReviews": { "nodes": [
            { "state": "APPROVED", "submittedAt": "2026-07-15T09:00:00Z", "author": { "login": "alice" } },
            { "state": "COMMENTED", "submittedAt": "2026-07-14T09:00:00Z", "author": { "login": "bob" } },
            { "state": "PENDING", "submittedAt": null, "author": { "login": "carol" } }
          ] }
        }
        """
        let node = try decoder.decode(GraphQL.PRNode.self, from: Data(json.utf8))
        let item = try XCTUnwrap(node.toPRItem(role: .author))
        XCTAssertEqual(item.reviewDecision, .approved)
        XCTAssertEqual(item.ci, .passing)
        XCTAssertEqual(item.roles, [.author])
        // PENDING (unsubmitted) review dropped; newest first.
        XCTAssertEqual(item.latestReviews.map(\.authorLogin), ["alice", "bob"])
        XCTAssertEqual(item.latestReviews.first?.state, .approved)
    }

    func testDecodePRNodeWithoutReviewFieldsStillMaps() throws {
        let json = """
        {
          "databaseId": 8,
          "number": 13,
          "title": "No reviews yet",
          "url": "https://github.com/o/r/pull/13",
          "isDraft": true,
          "createdAt": "2026-07-13T09:00:00Z",
          "updatedAt": "2026-07-15T10:00:00Z",
          "reviewDecision": null,
          "repository": { "nameWithOwner": "o/r" },
          "author": { "login": "me" },
          "commits": { "nodes": [] },
          "latestReviews": null
        }
        """
        let node = try decoder.decode(GraphQL.PRNode.self, from: Data(json.utf8))
        let item = try XCTUnwrap(node.toPRItem(role: nil))
        XCTAssertEqual(item.reviewDecision, ReviewDecision.none)
        XCTAssertTrue(item.latestReviews.isEmpty)
        XCTAssertTrue(item.roles.isEmpty)
    }
}
