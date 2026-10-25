import AppKit
import ActionsWatcherCore
import Combine
import ServiceManagement
import UserNotifications

enum AppScreen { case dashboard, repositories, settings, onboarding }
enum RunFilter: String, CaseIterable { case all = "Todas", active = "En curso", failed = "Fallidas" }

@MainActor
final class MonitorStore: ObservableObject {
    @Published var screen: AppScreen = .onboarding
    @Published var user: String?
    @Published var records: [RunRecord] = []
    @Published var repositories: [Repository] = []
    @Published var selectedRepositories: Set<String> = []
    @Published var selectedRun: RunRecord?
    @Published var jobs: [WorkflowJob] = []
    @Published var jobsLoading = false
    @Published var jobsError: String?
    @Published var isConnecting = false
    @Published var isRefreshing = false
    @Published var isLoadingRepositories = false
    @Published var canLoadMoreRepositories = false
    @Published var errorMessage: String?
    @Published var repositoryErrors: [String: String] = [:]
    @Published var lastUpdated: Date?
    @Published var nextRetry: Date?
    @Published var isDemo = false
    @Published var isPanelVisible = false
    @Published var filter: RunFilter = .all
    @Published var search = ""
    @Published var refreshInterval = 30
    @Published var notifyFailures = true
    @Published var notifySuccesses = false
    @Published var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published var launchAtLogin = false

    private let defaults: UserDefaults
    private var client: GitHubClient?
    private var pollTask: Task<Void, Never>?
    private var tracker = CompletionTracker()
    private var sessionID = UUID()
    private var jobsRequestID = UUID()
    private var repositoryPage = 1
    private var connectionMode: String?
    private var consecutiveFailures = 0
    private var retryUntil: Date?
    private var isSuspended = false

    init(demo: Bool = false) {
        defaults = .standard
        if demo { enterDemo(); return }
        selectedRepositories = Set(defaults.stringArray(forKey: "repositories") ?? [])
        let savedInterval = defaults.integer(forKey: "refreshInterval")
        refreshInterval = [15, 30, 60, 120].contains(savedInterval) ? savedInterval : 30
        notifyFailures = defaults.object(forKey: "notifyFailures") as? Bool ?? true
        notifySuccesses = defaults.bool(forKey: "notifySuccesses")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    var isConnected: Bool { user != nil }
    var activeCount: Int { records.filter { $0.run.state.isActive }.count }
    var summary: RunState { RunOrdering.summary(records) }
    var visibleRecords: [RunRecord] {
        RunOrdering.sorted(records.filter { record in
            let matchesFilter = filter == .all || (filter == .active && record.run.state.isActive) ||
                (filter == .failed && record.run.state == .failure)
            let matchesSearch = search.isEmpty || "\(record.repository) \(record.run.title) \(record.run.headBranch ?? "") \(record.run.workflowName)"
                .localizedCaseInsensitiveContains(search)
            return matchesFilter && matchesSearch
        })
    }

    func restoreSession() async {
        guard !isDemo else { return }
        await updateNotificationStatus()
        guard let mode = defaults.string(forKey: "connectionMode") else { return }
        await connect(token: nil, useCLI: mode == "cli", restoring: true)
    }

    func connect(token: String?, useCLI: Bool, restoring: Bool = false) async {
        guard !isConnecting else { return }
        isConnecting = true; errorMessage = nil
        let id = UUID(); sessionID = id
        defer { if sessionID == id { isConnecting = false } }
        do {
            let credential: String
            if useCLI { credential = try await CredentialStore.githubCLIToken() }
            else if let token { credential = token.trimmingCharacters(in: .whitespacesAndNewlines) }
            else { credential = try CredentialStore.load() ?? "" }
            guard !credential.isEmpty else { throw GitHubError.unauthorized }
            let newClient = GitHubClient(token: credential)
            let account = try await newClient.user()
            let repos = try await newClient.repositories()
            guard sessionID == id else { return }
            if !useCLI && !restoring { try CredentialStore.save(credential) }
            // CLI credentials remain owned by gh; the app only keeps them in memory.
            client = newClient; user = account.login; repositories = repos; repositoryPage = 1
            canLoadMoreRepositories = repos.count == 100
            isDemo = false; connectionMode = useCLI ? "cli" : "token"
            defaults.set(connectionMode, forKey: "connectionMode")
            screen = selectedRepositories.isEmpty ? .repositories : .dashboard
            startPolling()
            await refresh()
        } catch {
            guard sessionID == id else { return }
            errorMessage = error.localizedDescription
            screen = .onboarding
        }
    }

    func refresh() async {
        guard !isDemo, !isSuspended, !isRefreshing, let client, !selectedRepositories.isEmpty else { return }
        if let retryUntil, retryUntil > .now { nextRetry = retryUntil; return }
        let id = sessionID
        let selected = selectedRepositories.sorted()
        isRefreshing = true
        defer { if sessionID == id { isRefreshing = false } }
        var allFailed = true
        var latestError: String?
        var rateLimitDate: Date?
        // Bounded concurrency: at most three repositories are polled at once.
        for offset in stride(from: 0, to: selected.count, by: 3) {
            let batch = Array(selected[offset..<min(offset + 3, selected.count)])
            await withTaskGroup(of: RepoResult.self) { group in
                for repository in batch {
                    let previous = records.filter { $0.repository == repository }.map(\.run)
                    group.addTask {
                        do { return .success(repository, try await client.runs(repository: repository, tracking: previous)) }
                        catch { return .failure(repository, error.localizedDescription, (error as? GitHubError)) }
                    }
                }
                for await result in group {
                    guard sessionID == id else { continue }
                    switch result {
                    case .success(let repository, let runs):
                        guard selectedRepositories.contains(repository) else { continue }
                        records.removeAll { $0.repository == repository }
                        records += runs.map { RunRecord(repository: repository, run: $0) }
                        repositoryErrors.removeValue(forKey: repository)
                        allFailed = false
                    case .failure(let repository, let message, let apiError):
                        guard selectedRepositories.contains(repository) else { continue }
                        repositoryErrors[repository] = message
                        latestError = "\(repository): \(message)"
                        if case .rateLimited(let date) = apiError { rateLimitDate = date }
                    }
                }
            }
            if rateLimitDate != nil || sessionID != id { break }
        }
        guard sessionID == id else { return }
        records = RunOrdering.sorted(records)
        let completed = tracker.update(records)
        for record in completed { await sendNotification(record) }
        guard sessionID == id else { return }
        if !allFailed { lastUpdated = .now }
        errorMessage = latestError
        consecutiveFailures = allFailed ? consecutiveFailures + 1 : 0
        if let rateLimitDate { retryUntil = rateLimitDate }
        else if allFailed {
            retryUntil = .now.addingTimeInterval(min(300, Double(refreshInterval) * pow(2, Double(min(consecutiveFailures, 4)))))
        } else { retryUntil = nil }
        nextRetry = retryUntil
        if let selectedRun, let updated = records.first(where: { $0.id == selectedRun.id }) {
            self.selectedRun = updated
            await loadJobs(updated)
        }
    }

    func selectRun(_ record: RunRecord) {
        selectedRun = record; jobs = []; jobsError = nil
        Task { await loadJobs(record) }
    }

    func closeRun() { jobsRequestID = UUID(); selectedRun = nil; jobs = []; jobsLoading = false; jobsError = nil }

    func loadJobs(_ record: RunRecord) async {
        let requestID = UUID(); jobsRequestID = requestID
        jobsLoading = true; jobsError = nil
        defer { if jobsRequestID == requestID { jobsLoading = false } }
        if isDemo { jobs = DemoContent.jobs; return }
        guard let client else { return }
        do {
            let result = try await client.jobs(repository: record.repository, runID: record.run.id, attempt: record.run.attempt)
            guard jobsRequestID == requestID, selectedRun?.id == record.id else { return }
            jobs = result
        } catch {
            guard jobsRequestID == requestID, selectedRun?.id == record.id else { return }
            jobsError = error.localizedDescription
        }
    }

    func loadMoreRepositories() async {
        guard !isLoadingRepositories, let client else { return }
        let id = sessionID
        isLoadingRepositories = true
        defer { if sessionID == id { isLoadingRepositories = false } }
        do {
            let page = try await client.repositories(page: repositoryPage + 1)
            guard sessionID == id else { return }
            repositoryPage += 1
            let existing = Set(repositories.map(\.id))
            repositories += page.filter { !existing.contains($0.id) }
            canLoadMoreRepositories = page.count == 100
        } catch { if sessionID == id { errorMessage = error.localizedDescription } }
    }

    func addRepository(_ input: String) async -> Bool {
        guard let name = RepositoryLocator.parse(input) else {
            errorMessage = "Usa el formato propietario/repositorio o una URL de github.com."; return false
        }
        if selectedRepositories.contains(name) { return true }
        guard selectedRepositories.count < 10 else { errorMessage = "Puedes monitorear hasta 10 repositorios a la vez."; return false }
        if isDemo {
            if !repositories.contains(where: { $0.fullName == name }) {
                repositories.append(Repository(id: Int.random(in: 1000...9999), fullName: name))
            }
            toggleRepository(name); return true
        }
        guard let client else { return false }
        let id = sessionID
        do {
            let repo = try await client.repository(name)
            guard sessionID == id else { return false }
            if !repositories.contains(where: { $0.id == repo.id }) { repositories.insert(repo, at: 0) }
            if !selectedRepositories.contains(repo.fullName) { toggleRepository(repo.fullName) }
            errorMessage = nil; return true
        } catch { if sessionID == id { errorMessage = error.localizedDescription }; return false }
    }

    func toggleRepository(_ name: String) {
        if selectedRepositories.contains(name) {
            selectedRepositories.remove(name)
            records.removeAll { $0.repository == name }; repositoryErrors.removeValue(forKey: name)
            if selectedRun?.repository == name { closeRun() }
        } else if selectedRepositories.count < 10 { selectedRepositories.insert(name) }
        else { errorMessage = "Puedes monitorear hasta 10 repositorios a la vez." }
        persistSettings()
        if !isDemo { Task { await refresh() } }
    }

    func persistSettings() {
        guard !isDemo else { return }
        defaults.set(selectedRepositories.sorted(), forKey: "repositories")
        defaults.set(refreshInterval, forKey: "refreshInterval")
        defaults.set(notifyFailures, forKey: "notifyFailures")
        defaults.set(notifySuccesses, forKey: "notifySuccesses")
    }

    func setSuspended(_ value: Bool) { isSuspended = value }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !isDemo else { launchAtLogin = enabled; return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { errorMessage = "Autoriza ActionsWatcher en Ajustes del Sistema → General → Ítems de inicio." }
        } catch { errorMessage = "No pudimos cambiar el inicio automático: \(error.localizedDescription)" }
    }

    func requestNotifications() async {
        guard !isDemo else { notificationStatus = .authorized; return }
        do { _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        catch { errorMessage = error.localizedDescription }
        await updateNotificationStatus()
    }

    func updateNotificationStatus() async {
        guard !isDemo else { return }
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func signOut() {
        if isDemo { exitDemo(); return }
        do { try CredentialStore.delete() }
        catch { errorMessage = error.localizedDescription; return }
        resetSession()
        defaults.removeObject(forKey: "connectionMode")
        defaults.removeObject(forKey: "repositories")
    }

    private func resetSession() {
        sessionID = UUID(); jobsRequestID = UUID(); pollTask?.cancel(); pollTask = nil
        client = nil; user = nil; records = []; repositories = []; selectedRepositories = []
        selectedRun = nil; jobs = []; tracker = CompletionTracker(); lastUpdated = nil; nextRetry = nil
        retryUntil = nil; consecutiveFailures = 0; repositoryErrors = [:]; errorMessage = nil
        isConnecting = false; isRefreshing = false; isLoadingRepositories = false; jobsLoading = false
        search = ""; filter = .all; screen = .onboarding
    }

    func enterDemo() {
        resetSession(); isDemo = true; user = DemoContent.account
        repositories = DemoContent.repositories; selectedRepositories = Set(repositories.prefix(3).map(\.fullName))
        records = DemoContent.records; screen = .dashboard; lastUpdated = .now
    }

    func exitDemo() {
        isDemo = false; resetSession()
        selectedRepositories = Set(defaults.stringArray(forKey: "repositories") ?? [])
        Task { await restoreSession() }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do { try await Task.sleep(for: .seconds(self.refreshInterval)) } catch { return }
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    private func sendNotification(_ record: RunRecord) async {
        guard !isDemo, (record.run.state == .failure && notifyFailures) ||
                (record.run.state == .success && notifySuccesses) else { return }
        let content = UNMutableNotificationContent()
        content.title = record.run.state == .success ? "Workflow completado" : "Falló un workflow"
        content.subtitle = record.repository
        content.body = "\(record.run.workflowName) · \(record.run.headBranch ?? "sin rama") · #\(record.run.runNumber)"
        content.sound = .default
        content.userInfo = ["url": record.run.htmlURL.absoluteString]
        let request = UNNotificationRequest(identifier: "\(record.id)/\(record.run.attempt)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }
}

private enum RepoResult: Sendable {
    case success(String, [WorkflowRun])
    case failure(String, String, GitHubError?)
}
