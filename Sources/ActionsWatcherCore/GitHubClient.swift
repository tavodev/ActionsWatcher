import Foundation

public enum GitHubError: Error, LocalizedError, Sendable, Equatable {
    case unauthorized, forbidden, notFound, rateLimited(Date), server(Int), invalidResponse
    public var errorDescription: String? {
        switch self {
        case .unauthorized: "La sesión expiró o el token no es válido. Vuelve a conectar tu cuenta."
        case .forbidden: "GitHub rechazó el acceso. Revisa el permiso Actions: read y la autorización de tu organización."
        case .notFound: "No se encontró el repositorio o tu cuenta no tiene acceso."
        case .rateLimited(let date): "Límite de GitHub alcanzado. Reintentaremos después de las \(date.formatted(date: .omitted, time: .shortened))."
        case .server(let code): "GitHub respondió con un error (\(code)). Lo intentaremos de nuevo."
        case .invalidResponse: "GitHub devolvió una respuesta que no pudimos leer."
        }
    }
}

public actor GitHubClient {
    private struct CacheEntry { let data: Data; let etag: String }
    private let token: String
    private let session: URLSession
    private let baseURL: URL
    private var cache: [URL: CacheEntry] = [:]
    private var blockedUntil: Date?

    public init(token: String, session: URLSession? = nil,
                baseURL: URL = URL(string: "https://api.github.com")!) {
        self.token = token; self.baseURL = baseURL
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.urlCache = nil
        self.session = session ?? URLSession(configuration: config)
    }

    public func user() async throws -> GitHubUser { try await get("user") }

    public func repositories(page: Int = 1) async throws -> [Repository] {
        try await get("user/repos", query: ["sort": "pushed", "per_page": "100", "page": String(page)])
    }

    public func repository(_ fullName: String) async throws -> Repository {
        guard let validated = RepositoryLocator.parse(fullName) else { throw GitHubError.notFound }
        return try await get("repos/\(validated)")
    }

    public func runs(repository: String, tracking previousRuns: [WorkflowRun] = []) async throws -> [WorkflowRun] {
        guard let name = RepositoryLocator.parse(repository) else { throw GitHubError.notFound }
        let recent: RunsResponse = try await get("repos/\(name)/actions/runs", query: ["per_page": "20"])
        // Fetch active runs separately so a busy repo cannot hide running work behind recent completions.
        var records = Dictionary(recent.workflowRuns.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        for status in ["in_progress", "queued", "waiting", "pending", "requested"] {
            var page = 1
            while true {
                let active: RunsResponse = try await get("repos/\(name)/actions/runs", query: [
                    "status": status, "per_page": "100", "page": String(page)
                ])
                for run in active.workflowRuns { records[run.id] = run }
                if active.workflowRuns.count < 100 { break }
                page += 1
            }
        }
        // A long-running build can finish outside the 20 most recently created runs.
        // Resolve previously active runs that disappeared from the active endpoints.
        for previous in previousRuns where previous.state.isActive && records[previous.id] == nil {
            do {
                let resolved: WorkflowRun = try await get("repos/\(name)/actions/runs/\(previous.id)")
                records[resolved.id] = resolved
            } catch GitHubError.notFound {
                // Deleted runs no longer have a result to display.
                continue
            }
        }
        return records.values.sorted { $0.createdAt > $1.createdAt }
    }

    public func jobs(repository: String, runID: Int, attempt: Int) async throws -> [WorkflowJob] {
        guard let name = RepositoryLocator.parse(repository) else { throw GitHubError.notFound }
        var jobs: [WorkflowJob] = [], page = 1
        while true {
            let response: JobsResponse = try await get("repos/\(name)/actions/runs/\(runID)/attempts/\(attempt)/jobs",
                query: ["per_page": "100", "page": String(page)])
            jobs += response.jobs
            if response.jobs.count < 100 { return jobs }
            page += 1
        }
    }

    private func get<T: Decodable>(_ path: String, query: [String: String] = [:]) async throws -> T {
        if let blockedUntil, blockedUntil > .now { throw GitHubError.rateLimited(blockedUntil) }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query.sorted { $0.key < $1.key }.map(URLQueryItem.init)
        guard let url = components.url else { throw GitHubError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("ActionsWatcher/1.0", forHTTPHeaderField: "User-Agent")
        if let cached = cache[url] { request.setValue(cached.etag, forHTTPHeaderField: "If-None-Match") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw GitHubError.invalidResponse }
        let payload: Data
        if http.statusCode == 304, let cached = cache[url] {
            payload = cached.data
        } else if http.statusCode == 200 {
            payload = data
            if let etag = http.value(forHTTPHeaderField: "ETag") { cache[url] = CacheEntry(data: data, etag: etag) }
        } else {
            if http.statusCode == 429 || (http.statusCode == 403 &&
                (http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" ||
                 http.value(forHTTPHeaderField: "Retry-After") != nil ||
                 String(data: data, encoding: .utf8)?.localizedCaseInsensitiveContains("rate limit") == true)) {
                let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(Double.init).map { Date.now.addingTimeInterval($0) }
                let reset = http.value(forHTTPHeaderField: "X-RateLimit-Reset").flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
                let date = max(retry ?? reset ?? Date.now.addingTimeInterval(60), .now.addingTimeInterval(1))
                blockedUntil = date
                throw GitHubError.rateLimited(date)
            }
            switch http.statusCode {
            case 401: throw GitHubError.unauthorized
            case 403: throw GitHubError.forbidden
            case 404: throw GitHubError.notFound
            default: throw GitHubError.server(http.statusCode)
            }
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else { throw GitHubError.invalidResponse }
            return date
        }
        do { return try decoder.decode(T.self, from: payload) }
        catch { throw GitHubError.invalidResponse }
    }

    private struct RunsResponse: Decodable {
        let workflowRuns: [WorkflowRun]
        enum CodingKeys: String, CodingKey { case workflowRuns = "workflow_runs" }
    }
    private struct JobsResponse: Decodable { let jobs: [WorkflowJob] }
}
