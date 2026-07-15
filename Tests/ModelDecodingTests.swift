import XCTest
// Models under test are compiled into this test module directly (see project.yml).

final class ModelDecodingTests: XCTestCase {

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func testDecodeIssueSearchItemDerivesRepoFullName() throws {
        let json = """
        {
          "id": 1,
          "number": 42,
          "title": "Fix the flux capacitor",
          "html_url": "https://github.com/octo/repo/pull/42",
          "state": "open",
          "repository_url": "https://api.github.com/repos/octo/repo",
          "updated_at": "2026-07-15T10:00:00Z",
          "created_at": "2026-07-14T10:00:00Z",
          "pull_request": { "url": "https://api.github.com/repos/octo/repo/pulls/42" }
        }
        """
        let item = try decoder.decode(IssueSearchItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.repositoryFullName, "octo/repo")
        XCTAssertNotNil(item.pullRequest)
    }

    func testDecodeWorkflowRun() throws {
        let json = """
        {
          "id": 99,
          "name": "CI",
          "head_branch": "main",
          "status": "completed",
          "conclusion": "failure",
          "html_url": "https://github.com/octo/repo/actions/runs/99",
          "event": "push",
          "created_at": "2026-07-15T09:00:00Z",
          "updated_at": "2026-07-15T09:05:00Z",
          "run_started_at": "2026-07-15T09:00:30Z"
        }
        """
        let run = try decoder.decode(WorkflowRun.self, from: Data(json.utf8))
        XCTAssertEqual(run.conclusion, "failure")
        XCTAssertEqual(run.headBranch, "main")
    }

    func testDecodeNotification() throws {
        let json = """
        {
          "id": "123",
          "unread": true,
          "reason": "mention",
          "updated_at": "2026-07-15T08:00:00Z",
          "subject": { "title": "You were mentioned", "url": "https://api.github.com/repos/octo/repo/issues/7", "type": "Issue" },
          "repository": { "full_name": "octo/repo", "html_url": "https://github.com/octo/repo" }
        }
        """
        let notif = try decoder.decode(GitHubNotification.self, from: Data(json.utf8))
        XCTAssertEqual(notif.reason, "mention")
        XCTAssertEqual(notif.repository.fullName, "octo/repo")
    }

    func testCIStatusMapping() {
        XCTAssertEqual(CIStatus.from(rollupState: "SUCCESS"), .passing)
        XCTAssertEqual(CIStatus.from(rollupState: "FAILURE"), .failing)
        XCTAssertEqual(CIStatus.from(rollupState: "ERROR"), .failing)
        XCTAssertEqual(CIStatus.from(rollupState: "PENDING"), .pending)
        XCTAssertEqual(CIStatus.from(rollupState: "EXPECTED"), .pending)
        XCTAssertEqual(CIStatus.from(rollupState: nil), CIStatus.none)
    }

    func testRunItemDerivedState() {
        let running = RunItem(id: 1, workflowName: "CI", branch: "dev", repositoryFullName: "o/r",
                              url: URL(string: "https://github.com")!, status: "in_progress",
                              conclusion: nil, startedAt: Date(timeIntervalSince1970: 0),
                              updatedAt: Date(timeIntervalSince1970: 80))
        XCTAssertTrue(running.isRunning)
        XCTAssertFalse(running.didFail)
        XCTAssertEqual(running.duration, 80)

        let failed = RunItem(id: 2, workflowName: "CI", branch: "dev", repositoryFullName: "o/r",
                             url: URL(string: "https://github.com")!, status: "completed",
                             conclusion: "failure", startedAt: Date(), updatedAt: Date())
        XCTAssertFalse(failed.isRunning)
        XCTAssertTrue(failed.didFail)
    }
}
