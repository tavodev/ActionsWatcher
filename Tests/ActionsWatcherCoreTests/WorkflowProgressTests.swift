import XCTest
@testable import ActionsWatcherCore

final class WorkflowProgressTests: XCTestCase {
    func testEmptyProgressHasNoInventedPercentage() {
        let progress = WorkflowProgress(jobs: [])
        XCTAssertEqual(progress.total, 0)
        XCTAssertEqual(progress.finished, 0)
        XCTAssertEqual(progress.fraction, 0)
    }

    func testTerminalResultsCountAsFinishedWithoutBeingReportedAsSuccessful() {
        let jobs = [job(1, "completed", "success"), job(2, "completed", "failure"),
            job(3, "completed", "cancelled"), job(4, "completed", "skipped"),
            job(5, "in_progress"), job(6, "queued")]
        let progress = WorkflowProgress(jobs: jobs)
        XCTAssertEqual(progress.total, 6)
        XCTAssertEqual(progress.finished, 4)
        XCTAssertEqual(progress.succeeded, 1)
        XCTAssertEqual(progress.failed, 1)
        XCTAssertEqual(progress.running, 1)
        XCTAssertEqual(progress.queued, 1)
        XCTAssertEqual(progress.fraction, 4.0 / 6.0, accuracy: 0.0001)
    }

    func testStepProgressDoesNotConfuseRunningWithDone() {
        let steps = [WorkflowStep(name: "Setup", status: "completed", conclusion: "success", number: 1),
            WorkflowStep(name: "Test", status: "in_progress", number: 2),
            WorkflowStep(name: "Upload", status: "queued", number: 3)]
        let progress = WorkflowProgress(steps: steps)
        XCTAssertEqual(progress.finished, 1)
        XCTAssertEqual(progress.running, 1)
        XCTAssertEqual(progress.fraction, 1.0 / 3.0, accuracy: 0.0001)
    }

    func testSelectionSurvivesRefreshAndDefaultsToActionableJobs() {
        let jobs = [job(1, "completed", "success"), job(2, "queued"),
            job(3, "in_progress"), job(4, "completed", "failure")]
        XCTAssertEqual(JobFocus.preferred(in: jobs)?.id, 4)
        XCTAssertEqual(JobFocus.preferred(in: jobs, selectedID: 1)?.id, 1)
        XCTAssertEqual(JobFocus.preferred(in: jobs, selectedID: 999)?.id, 4)
        XCTAssertNil(JobFocus.preferred(in: []))
    }

    func testEqualStatesKeepTheirOriginalOrder() {
        let jobs = [job(4, "in_progress"), job(2, "in_progress"), job(1, "completed", "success")]
        XCTAssertEqual(JobFocus.ordered(jobs).map(\.id), [4, 2, 1])
    }

    func testActionSHAsAreShortenedWithoutChangingTheOriginalName() {
        let name = "Run actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
        let step = WorkflowStep(name: name, status: "completed", conclusion: "success", number: 1)
        XCTAssertEqual(step.compactName, "Run actions/checkout@3d3c42e")
        XCTAssertEqual(step.name, name)
        XCTAssertEqual(WorkflowStep(name: "Run tests @v4", status: "queued", number: 2).compactName, "Run tests @v4")
    }

    private func job(_ id: Int, _ status: String, _ conclusion: String? = nil) -> WorkflowJob {
        WorkflowJob(id: id, name: "Job \(id)", status: status, conclusion: conclusion, steps: [])
    }
}
