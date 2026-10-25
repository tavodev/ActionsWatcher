import Foundation

public struct WorkflowProgress: Sendable, Equatable {
    public let total: Int
    public let finished: Int
    public let succeeded: Int
    public let failed: Int
    public let running: Int
    public let queued: Int

    public var fraction: Double { total == 0 ? 0 : Double(finished) / Double(total) }

    public init(jobs: [WorkflowJob]) { self.init(states: jobs.map { ($0.status, $0.state) }) }
    public init(steps: [WorkflowStep]) { self.init(states: steps.map { ($0.status, $0.state) }) }

    private init(states: [(String, RunState)]) {
        total = states.count
        finished = states.filter { $0.0 == "completed" }.count
        succeeded = states.filter { $0.1 == .success }.count
        failed = states.filter { $0.1 == .failure }.count
        running = states.filter { $0.1 == .running }.count
        queued = states.filter { $0.1 == .queued }.count
    }
}

public enum JobFocus {
    public static func ordered(_ jobs: [WorkflowJob]) -> [WorkflowJob] {
        jobs.enumerated().sorted {
            let left = priority($0.element.state), right = priority($1.element.state)
            return left == right ? $0.offset < $1.offset : left < right
        }.map(\.element)
    }

    public static func preferred(in jobs: [WorkflowJob], selectedID: Int? = nil) -> WorkflowJob? {
        if let selectedID, let selected = jobs.first(where: { $0.id == selectedID }) { return selected }
        return ordered(jobs).first
    }

    private static func priority(_ state: RunState) -> Int {
        switch state {
        case .failure: 0
        case .running: 1
        case .queued: 2
        case .success: 3
        case .cancelled, .neutral: 4
        }
    }
}

extension WorkflowStep {
    public var compactName: String {
        name.replacingOccurrences(of: "@([0-9a-fA-F]{7})[0-9a-fA-F]{33}(?=$|[^0-9a-fA-F])",
            with: "@$1", options: .regularExpression)
    }
}
