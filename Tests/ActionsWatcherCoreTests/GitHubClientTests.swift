import Foundation
import XCTest
@testable import ActionsWatcherCore

final class GitHubClientTests: XCTestCase, @unchecked Sendable {
    override func tearDown() { MockURLProtocol.stub.set(nil); super.tearDown() }

    func testAuthenticatedReadRequestAndConditionalCache() async throws {
        let requests = RequestLog()
        MockURLProtocol.stub.set { request in
            requests.append(request)
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/vnd.github+json")
            if requests.count == 1 { return (200, ["ETag": "\"version-1\""], Data("{\"login\":\"octocat\"}".utf8)) }
            XCTAssertEqual(request.value(forHTTPHeaderField: "If-None-Match"), "\"version-1\"")
            return (304, [:], Data())
        }
        let client = makeClient()
        let first = try await client.user(), cached = try await client.user()
        XCTAssertEqual(first.login, "octocat")
        XCTAssertEqual(cached.login, "octocat")
        XCTAssertEqual(requests.count, 2)
    }

    func testExpiredTokenAndMissingRepositoryErrors() async throws {
        MockURLProtocol.stub.set { _ in (401, [:], Data()) }
        do { _ = try await makeClient().user(); XCTFail("Expected unauthorized") }
        catch { XCTAssertEqual(error as? GitHubError, .unauthorized) }
        MockURLProtocol.stub.set { _ in (404, [:], Data()) }
        do { _ = try await makeClient().repository("owner/private"); XCTFail("Expected not found") }
        catch { XCTAssertEqual(error as? GitHubError, .notFound) }
    }

    func testRateLimitStopsFurtherNetworkRequestsUntilReset() async throws {
        let requests = RequestLog()
        MockURLProtocol.stub.set { request in
            requests.append(request)
            return (403, ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(Date.now.addingTimeInterval(600).timeIntervalSince1970)], Data())
        }
        let client = makeClient()
        for _ in 0..<2 {
            do { _ = try await client.user(); XCTFail("Expected rate limit") }
            catch { guard case .rateLimited(let date) = error as? GitHubError else { return XCTFail("Unexpected \(error)") }; XCTAssertGreaterThan(date, .now) }
        }
        XCTAssertEqual(requests.count, 1)
    }

    func testSecondaryRateLimitHonorsRetryAfter() async throws {
        MockURLProtocol.stub.set { _ in (429, ["Retry-After": "120"], Data()) }
        do { _ = try await makeClient().user(); XCTFail("Expected rate limit") }
        catch {
            guard case .rateLimited(let date) = error as? GitHubError else { return XCTFail("Wrong error") }
            XCTAssertGreaterThan(date.timeIntervalSinceNow, 110)
        }
    }

    func testPermissionErrorDoesNotMasqueradeAsRateLimit() async throws {
        MockURLProtocol.stub.set { _ in (403, [:], Data("{\"message\":\"Resource not accessible\"}".utf8)) }
        do { _ = try await makeClient().user(); XCTFail("Expected forbidden") }
        catch { XCTAssertEqual(error as? GitHubError, .forbidden) }
    }

    func testRepositoryPageAndJobAttemptPagination() async throws {
        let requests = RequestLog()
        MockURLProtocol.stub.set { request in
            requests.append(request)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let page = query.first(where: { $0.name == "page" })!.value!
            if request.url!.path == "/user/repos" {
                XCTAssertEqual(page, "2")
                return (200, [:], Data("[]".utf8))
            }
            XCTAssertEqual(request.url!.path, "/repos/owner/repo/actions/runs/42/attempts/3/jobs")
            let jobs = page == "1" ? (0..<100).map { WorkflowJob(id: $0, name: "matrix-\($0)", status: "completed", conclusion: "success", steps: []) } : []
            return (200, [:], try JSONEncoder().encode(["jobs": jobs]))
        }
        let client = makeClient()
        _ = try await client.repositories(page: 2)
        let jobs = try await client.jobs(repository: "owner/repo", runID: 42, attempt: 3)
        XCTAssertEqual(jobs.count, 100)
        XCTAssertEqual(requests.count, 3)
    }

    func testActiveRunsOutsideRecentPageAreNotLost() async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let recent = WorkflowRun(id: 1, name: "CI", title: "Recent", branch: "main", status: "completed", conclusion: "success")
        let active = WorkflowRun(id: 900, name: "Slow build", title: "Old but active", branch: "main", status: "in_progress", date: .now.addingTimeInterval(-90000))
        let recentData = try encoder.encode(["workflow_runs": [recent]])
        let activeData = try encoder.encode(["workflow_runs": [active]])
        MockURLProtocol.stub.set { request in
            let status = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems?.first(where: { $0.name == "status" })?.value
            return (200, [:], status == nil ? recentData : status == "in_progress" ? activeData : Data("{\"workflow_runs\":[]}".utf8))
        }
        let runs = try await makeClient().runs(repository: "owner/repo")
        XCTAssertEqual(Set(runs.map(\.id)), [1, 900])
    }

    func testMalformedResponseIsReported() async throws {
        MockURLProtocol.stub.set { _ in (200, [:], Data("{\"unexpected\":true}".utf8)) }
        do { _ = try await makeClient().user(); XCTFail("Expected invalid response") }
        catch { XCTAssertEqual(error as? GitHubError, .invalidResponse) }
    }

    func testOldActiveRunsAreResolvedAfterFinishingOutsideRecentPage() async throws {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let active = WorkflowRun(id: 900, name: "CI", title: "Long build", branch: "main", status: "in_progress")
        let completed = WorkflowRun(id: 900, name: "CI", title: "Long build", branch: "main", status: "completed", conclusion: "failure")
        let result = try encoder.encode(completed)
        let requests = RequestLog()
        MockURLProtocol.stub.set { request in
            requests.append(request)
            if request.url!.path.hasSuffix("/900") { return (200, [:], result) }
            return (200, [:], Data("{\"workflow_runs\":[]}".utf8))
        }
        let runs = try await makeClient().runs(repository: "owner/repo", tracking: [active])
        XCTAssertEqual(runs.first?.state, .failure)
        var tracker = CompletionTracker()
        _ = tracker.update([RunRecord(repository: "owner/repo", run: active)])
        XCTAssertEqual(tracker.update(runs.map { RunRecord(repository: "owner/repo", run: $0) }).count, 1)
        XCTAssertEqual(requests.count, 7)
    }

    private func makeClient() -> GitHubClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return GitHubClient(token: "test-token", session: URLSession(configuration: config))
    }
}

private final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (Int, [String: String], Data)
    static let stub = StubStore()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.stub.get() else { throw GitHubError.invalidResponse }
            let (status, headers, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private final class StubStore: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: MockURLProtocol.Handler?
    func set(_ value: MockURLProtocol.Handler?) { lock.withLock { handler = value } }
    func get() -> MockURLProtocol.Handler? { lock.withLock { handler } }
}

private final class RequestLog: @unchecked Sendable {
    private let lock = NSLock()
    private var requests: [URLRequest] = []
    var count: Int { lock.withLock { requests.count } }
    func append(_ request: URLRequest) { lock.withLock { requests.append(request) } }
}
