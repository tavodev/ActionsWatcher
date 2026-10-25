import ActionsWatcherCore
import Foundation

enum DemoContent {
    static let account = "actionswatcher-demo"
    private static let appRepository = "\(account)/sample-app"
    private static let siteRepository = "\(account)/sample-site"
    private static let apiRepository = "\(account)/sample-api"

    static var repositories: [Repository] { [
        Repository(id: 1, fullName: appRepository, isPrivate: true),
        Repository(id: 2, fullName: siteRepository),
        Repository(id: 3, fullName: apiRepository, isPrivate: true),
        Repository(id: 4, fullName: "\(account)/sample-design-system")
    ] }
    static var records: [RunRecord] { [
        RunRecord(repository: appRepository, run: WorkflowRun(id: 128, name: "Build & test", title: "feat: your CI, a little closer", branch: "main", status: "in_progress", date: .now.addingTimeInterval(-132))),
        RunRecord(repository: siteRepository, run: WorkflowRun(id: 84, name: "Deploy preview", title: "Update the landing page", branch: "feat/new-home", status: "queued", date: .now.addingTimeInterval(-48))),
        RunRecord(repository: apiRepository, run: WorkflowRun(id: 317, name: "CI", title: "fix: handle expired sessions", branch: "fix/auth", status: "completed", conclusion: "failure", date: .now.addingTimeInterval(-1080))),
        RunRecord(repository: siteRepository, run: WorkflowRun(id: 83, name: "Production", title: "Ship something good", branch: "main", status: "completed", conclusion: "success", date: .now.addingTimeInterval(-2520))),
        RunRecord(repository: appRepository, run: WorkflowRun(id: 127, name: "Build & test", title: "chore: update dependencies", branch: "main", status: "completed", conclusion: "success", date: .now.addingTimeInterval(-5400)))
    ] }
    static var jobs: [WorkflowJob] { [
        WorkflowJob(id: 1, name: "Lint & format", status: "completed", conclusion: "success", steps: [
            WorkflowStep(name: "Check out repository", status: "completed", conclusion: "success", number: 1),
            WorkflowStep(name: "Check formatting", status: "completed", conclusion: "success", number: 2)
        ]),
        WorkflowJob(id: 2, name: "Build · macOS", status: "completed", conclusion: "success", steps: [
            WorkflowStep(name: "Set up job", status: "completed", conclusion: "success", number: 1),
            WorkflowStep(name: "Check out repository", status: "completed", conclusion: "success", number: 2),
            WorkflowStep(name: "Build release", status: "completed", conclusion: "success", number: 3),
            WorkflowStep(name: "Upload artifacts", status: "completed", conclusion: "success", number: 4)
        ]),
        WorkflowJob(id: 3, name: "Tests shard 1/4", status: "completed", conclusion: "success", steps: shardSteps(completed: 9)),
        WorkflowJob(id: 4, name: "Tests shard 2/4", status: "in_progress", steps: shardSteps(completed: 6)),
        WorkflowJob(id: 5, name: "Tests shard 3/4", status: "in_progress", steps: shardSteps(completed: 5)),
        WorkflowJob(id: 6, name: "Tests shard 4/4", status: "queued", steps: []),
        WorkflowJob(id: 7, name: "Package release", status: "queued", steps: [])
    ] }

    static var failedJobs: [WorkflowJob] {
        jobs.map { job in
            if job.id == 4 {
                return WorkflowJob(id: job.id, name: job.name, status: "completed", conclusion: "failure", steps: shardSteps(completed: 6, failed: true))
            }
            return WorkflowJob(id: job.id, name: job.name, status: "completed", conclusion: job.id > 4 ? "cancelled" : "success",
                steps: (job.steps ?? []).map { WorkflowStep(name: $0.name, status: "completed", conclusion: job.id > 4 ? "cancelled" : "success", number: $0.number) })
        }
    }

    private static func shardSteps(completed: Int, failed: Bool = false) -> [WorkflowStep] {
        let names = ["Set up job", "Run actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1",
            "Restore dependency cache", "Run subosito/flutter-action@a449444c387b1966244ae4d4f8c696479add0b2",
            "Install SQLite", "Locked dependencies", "Tests shard", "Record runtime", "Shard runtime"]
        return names.enumerated().map { index, name in
            if index < completed { return WorkflowStep(name: name, status: "completed", conclusion: "success", number: index + 1) }
            if failed { return WorkflowStep(name: name, status: "completed", conclusion: index == completed ? "failure" : "skipped", number: index + 1) }
            return WorkflowStep(name: name, status: index == completed ? "in_progress" : "queued", number: index + 1)
        }
    }
}
