import XCTest
@testable import ActionsWatcherCore

final class MonitorTests: XCTestCase {
    func testRepositoryURLsAndNames() {
        XCTAssertEqual(RepositoryLocator.parse("  owner/sample-app \n"), "owner/sample-app")
        XCTAssertEqual(RepositoryLocator.parse("https://github.com/owner/sample-app.git/"), "owner/sample-app")
        for invalid in ["../repo", "owner/..", "owner/repo/actions", "https://evil.com/owner/repo", "owner/repo?token=x", "owner//repo", "owner/repo name", "owner/%2e%2e"] {
            XCTAssertNil(RepositoryLocator.parse(invalid), invalid)
        }
    }

    func testAllActiveAndTerminalStates() {
        for status in ["queued", "waiting", "pending", "requested", "in_progress"] {
            XCTAssertTrue(RunState(status: status, conclusion: nil).isActive, status)
        }
        for conclusion in ["failure", "timed_out", "startup_failure", "action_required"] {
            XCTAssertEqual(RunState(status: "completed", conclusion: conclusion), .failure)
        }
        XCTAssertEqual(RunState(status: "completed", conclusion: "cancelled"), .cancelled)
        XCTAssertEqual(RunState(status: "completed", conclusion: "skipped"), .neutral)
        XCTAssertEqual(RunState(status: "completed", conclusion: nil), .neutral)
    }

    func testNoHistoricalNotificationAndExactlyOneCompletion() {
        var tracker = CompletionTracker()
        XCTAssertTrue(tracker.update([record(1, "completed", "failure")]).isEmpty)
        XCTAssertTrue(tracker.update([record(1, "completed", "failure"), record(2, "in_progress")]).isEmpty)
        XCTAssertEqual(tracker.update([record(1, "completed", "failure"), record(2, "completed", "success")]).map(\.run.id), [2])
        XCTAssertTrue(tracker.update([record(2, "completed", "success")]).isEmpty)
        XCTAssertTrue(tracker.update([record(3, "completed", "failure")]).isEmpty)
    }

    func testRerunAttemptsDoNotProduceFalseCompletions() {
        var tracker = CompletionTracker()
        _ = tracker.update([record(1, "in_progress", attempt: 1)])
        XCTAssertTrue(tracker.update([record(1, "completed", "success", attempt: 2)]).isEmpty)
        _ = tracker.update([record(1, "in_progress", attempt: 3)])
        XCTAssertEqual(tracker.update([record(1, "completed", "failure", attempt: 3)]).count, 1)
        XCTAssertTrue(tracker.update([record(1, "completed", "failure", attempt: 3)]).isEmpty)
    }

    func testOldFailuresDoNotKeepIndicatorRedAfterSuccessfulRerun() {
        let old = record(1, "completed", "failure", date: Date(timeIntervalSince1970: 100))
        let newer = record(2, "completed", "success", date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(RunOrdering.summary([old, newer]), .success)
        XCTAssertEqual(RunOrdering.summary([old, newer, record(3, "queued")]), .queued)
        XCTAssertEqual(RunOrdering.summary([old, newer, record(4, "in_progress")]), .running)
        XCTAssertEqual(RunOrdering.summary([]), .neutral)
    }

    func testFailuresOnOtherRepositoriesAndBranchesRemainVisible() {
        let failure = record(1, "completed", "failure", branch: "fix/auth")
        let success = record(2, "completed", "success", branch: "main")
        XCTAssertEqual(RunOrdering.summary([failure, success]), .failure)
        let other = RunRecord(repository: "other/repo", run: success.run)
        XCTAssertEqual(RunOrdering.summary([failure, other]), .failure)
    }

    func testActiveRunsAppearBeforeRecentCompletedRuns() {
        let active = record(1, "in_progress", date: Date(timeIntervalSince1970: 100))
        let finished = record(2, "completed", "success", date: Date(timeIntervalSince1970: 200))
        XCTAssertEqual(RunOrdering.sorted([finished, active]).map(\.run.id), [1, 2])
    }

    func testWorkflowsWithIdenticalNamesAreIndependent() {
        let failure = WorkflowRun(id: 1, name: "CI", title: "One", branch: "main", status: "completed", conclusion: "failure", workflowID: 10)
        let success = WorkflowRun(id: 2, name: "CI", title: "Two", branch: "main", status: "completed", conclusion: "success", workflowID: 20)
        XCTAssertEqual(RunOrdering.summary([RunRecord(repository: "owner/repo", run: failure), RunRecord(repository: "owner/repo", run: success)]), .failure)
    }

    func testSummaryBreaksTimestampTiesUsingRunID() {
        let date = Date(timeIntervalSince1970: 100)
        let failure = record(1, "completed", "failure", date: date)
        let success = record(2, "completed", "success", date: date)
        XCTAssertEqual(RunOrdering.summary([failure, success]), .success)
        XCTAssertEqual(RunOrdering.summary([success, failure]), .success)
    }

    private func record(_ id: Int, _ status: String, _ conclusion: String? = nil,
                        attempt: Int = 1, date: Date = .now, branch: String = "main") -> RunRecord {
        RunRecord(repository: "owner/repo", run: WorkflowRun(id: id, name: "CI", title: "Commit", branch: branch,
            status: status, conclusion: conclusion, date: date, attempt: attempt))
    }
}
