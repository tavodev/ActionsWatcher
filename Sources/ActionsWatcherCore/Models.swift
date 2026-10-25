import Foundation

public struct GitHubUser: Codable, Sendable {
    public let login: String
}

public struct Repository: Codable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let name: String
    public let fullName: String
    public let isPrivate: Bool
    public let archived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, archived
        case fullName = "full_name"
        case isPrivate = "private"
    }

    public init(id: Int, fullName: String, isPrivate: Bool = false, archived: Bool = false) {
        self.id = id
        self.name = fullName.split(separator: "/").last.map(String.init) ?? fullName
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.archived = archived
    }
}

public enum RunState: String, Sendable, CaseIterable {
    case running, queued, success, failure, cancelled, neutral

    public init(status: String, conclusion: String?) {
        if status == "completed" {
            switch conclusion {
            case "success": self = .success
            case "failure", "timed_out", "startup_failure", "action_required": self = .failure
            case "cancelled": self = .cancelled
            default: self = .neutral
            }
        } else {
            self = status == "in_progress" ? .running : .queued
        }
    }

    public var isActive: Bool { self == .running || self == .queued }
    public var label: String {
        switch self {
        case .running: "En curso"
        case .queued: "En espera"
        case .success: "Completado"
        case .failure: "Falló"
        case .cancelled: "Cancelado"
        case .neutral: "Omitido"
        }
    }
}

public struct WorkflowRun: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String?
    public let displayTitle: String?
    public let headBranch: String?
    public let headSHA: String
    public let event: String
    public let status: String
    public let conclusion: String?
    public let htmlURL: URL
    public let createdAt: Date
    public let updatedAt: Date
    public let runStartedAt: Date?
    public let runNumber: Int
    public let runAttempt: Int?
    public let workflowID: Int?

    public var state: RunState { RunState(status: status, conclusion: conclusion) }
    public var title: String { displayTitle ?? name ?? "Workflow" }
    public var workflowName: String { name ?? "Workflow" }
    public var attempt: Int { runAttempt ?? 1 }
    public var startedAt: Date { runStartedAt ?? createdAt }

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion
        case displayTitle = "display_title", headBranch = "head_branch", headSHA = "head_sha"
        case htmlURL = "html_url", createdAt = "created_at", updatedAt = "updated_at"
        case runStartedAt = "run_started_at", runNumber = "run_number", runAttempt = "run_attempt"
        case workflowID = "workflow_id"
    }

    public init(id: Int, name: String, title: String, branch: String, status: String,
                conclusion: String? = nil, date: Date = .now, attempt: Int = 1, workflowID: Int? = nil) {
        self.id = id; self.name = name; self.displayTitle = title; self.headBranch = branch
        self.headSHA = "a3f8c21d9b6e4f0123456789abcdef0123456789ab"
        self.event = "push"; self.status = status; self.conclusion = conclusion
        self.htmlURL = URL(string: "https://github.com/octocat/Hello-World/actions/runs/\(id)")!
        self.createdAt = date; self.updatedAt = date.addingTimeInterval(86)
        self.runStartedAt = date; self.runNumber = id; self.runAttempt = attempt
        self.workflowID = workflowID
    }
}

public struct RunRecord: Identifiable, Sendable {
    public let repository: String
    public let run: WorkflowRun
    public var id: String { "\(repository)/\(run.id)" }
    public init(repository: String, run: WorkflowRun) { self.repository = repository; self.run = run }
}

public struct WorkflowStep: Codable, Identifiable, Sendable {
    public let name: String
    public let status: String
    public let conclusion: String?
    public let number: Int
    public var id: Int { number }
    public var state: RunState { RunState(status: status, conclusion: conclusion) }
    public init(name: String, status: String, conclusion: String? = nil, number: Int) {
        self.name = name; self.status = status; self.conclusion = conclusion; self.number = number
    }
}

public struct WorkflowJob: Codable, Identifiable, Sendable {
    public let id: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let steps: [WorkflowStep]?
    public var state: RunState { RunState(status: status, conclusion: conclusion) }
    public init(id: Int, name: String, status: String, conclusion: String? = nil, steps: [WorkflowStep]) {
        self.id = id; self.name = name; self.status = status; self.conclusion = conclusion; self.steps = steps
    }
}

public enum RepositoryLocator {
    public static func parse(_ input: String) -> String? {
        var value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("https://github.com/") { value.removeFirst("https://github.com/".count) }
        if value.hasSuffix("/") { value.removeLast() }
        if value.hasSuffix(".git") { value.removeLast(4) }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              parts[0].range(of: "^[A-Za-z0-9][A-Za-z0-9-]*$", options: .regularExpression) != nil,
              parts[1].range(of: "^[A-Za-z0-9_.-]+$", options: .regularExpression) != nil,
              parts[1] != ".", parts[1] != ".." else { return nil }
        return value
    }
}

/// Only transitions observed by this session generate notifications, including reruns.
public struct CompletionTracker: Sendable {
    private var observed: [String: (attempt: Int, active: Bool)] = [:]
    public init() {}

    public mutating func update(_ records: [RunRecord]) -> [RunRecord] {
        var completed: [RunRecord] = []
        for record in records {
            if let previous = observed[record.id], previous.active,
               previous.attempt == record.run.attempt, !record.run.state.isActive {
                completed.append(record)
            }
            observed[record.id] = (record.run.attempt, record.run.state.isActive)
        }
        // The store supplies its bounded, current snapshot, including temporarily stale repositories.
        let present = Set(records.map(\.id))
        observed = observed.filter { present.contains($0.key) }
        return completed
    }
}

public enum RunOrdering {
    public static func sorted(_ records: [RunRecord]) -> [RunRecord] {
        records.sorted {
            if $0.run.state.isActive != $1.run.state.isActive { return $0.run.state.isActive }
            if $0.run.createdAt != $1.run.createdAt { return $0.run.createdAt > $1.run.createdAt }
            return $0.id < $1.id
        }
    }

    public static func summary(_ records: [RunRecord]) -> RunState {
        if records.contains(where: { $0.run.state == .running }) { return .running }
        if records.contains(where: { $0.run.state == .queued }) { return .queued }
        // Only the latest run of each workflow/branch contributes to the resting indicator.
        let latest = Dictionary(grouping: records) {
            "\($0.repository)/\($0.run.workflowID.map(String.init) ?? $0.run.workflowName)/\($0.run.headBranch ?? "")"
        }.values.compactMap { group in
            group.max { lhs, rhs in
                lhs.run.createdAt == rhs.run.createdAt ? lhs.run.id < rhs.run.id : lhs.run.createdAt < rhs.run.createdAt
            }
        }
        if latest.contains(where: { $0.run.state == .failure }) { return .failure }
        return latest.contains(where: { $0.run.state == .success }) ? .success : .neutral
    }
}
