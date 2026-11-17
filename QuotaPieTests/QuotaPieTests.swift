import Foundation
import Testing
@testable import QuotaPie

struct ModelTests {
    @Test(arguments: [(0.0, 100.0), (100, 0), (37.5, 62.5)])
    func percentage(pair: (Double, Double)) {
        let window = UsageWindow(id: "a", name: "Test", usedPercent: pair.0, resetAt: nil, durationMinutes: nil)
        #expect(window.availablePercent == pair.1)
    }
    @Test func unknownAndInvalid() {
        for value in [nil, -1, 101, Double.nan, Double.infinity] as [Double?] {
            #expect(UsageWindow(id: "a", name: "", usedPercent: value, resetAt: nil, durationMinutes: nil).availablePercent == nil)
        }
    }
    @Test func timestampsAndTimezones() throws {
        let date = try #require(UsageWindow.date(seconds: 1730947200))
        #expect(date.timeIntervalSince1970 == 1730947200)
        #expect(UsageWindow.date(seconds: .infinity) == nil)
        #expect(UsageWindow.date(seconds: -10) == nil)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        var brazil = utc
        brazil.timeZone = try #require(TimeZone(identifier: "America/Sao_Paulo"))
        #expect(utc.component(.hour, from: date) != brazil.component(.hour, from: date))
        let snapshot = UsageSnapshot(provider: .codex, windows: [
            .init(id: "a", name: "", usedPercent: 50, resetAt: date, durationMinutes: 300)
        ], fetchedAt: date.addingTimeInterval(-30), source: .officialAppServer, state: .connected)
        #expect(snapshot.isStale(at: date.addingTimeInterval(1), interval: 120))
        #expect(!snapshot.isStale(at: date.addingTimeInterval(-1), interval: 120))
    }
}

struct ParserTests {
    @Test func codexMultiBucket() throws {
        let data = Data(#"{"rateLimits":{"primary":{"usedPercent":99}},"rateLimitsByLimitId":{"codex":{"limitId":"codex","primary":{"usedPercent":37.5,"windowDurationMins":300,"resetsAt":1730947200},"secondary":{"usedPercent":100,"windowDurationMins":10080,"resetsAt":1730947500},"futureField":true},"review":{"primary":{"usedPercent":0}}}}"#.utf8)
        let result = try CodexRateLimits.parse(data)
        #expect(result.windows.count == 3)
        #expect(result.windows[0].availablePercent == 62.5)
        #expect(result.windows[1].availablePercent == 0)
        #expect(result.windows[2].availablePercent == 100)
        #expect(result.state == .partial)
    }
    @Test func incompleteRemainsUnknown() throws {
        let result = try CodexRateLimits.parse(Data(#"{"rateLimits":{"primary":{},"secondary":null}}"#.utf8))
        #expect(result.windows.count == 1)
        #expect(result.windows[0].availablePercent == nil)
        #expect(result.windows[0].resetAt == nil)
        #expect(result.state == .partial)
    }
    @Test(arguments: ["", "{}", "[]", #"{"rateLimits":{"primary":{"usedPercent":"changed"}}}"#])
    func invalidSchema(json: String) {
        #expect(throws: UsageFetchError.invalidResponse) { try CodexRateLimits.parse(Data(json.utf8)) }
    }
    @Test func emptyBuckets() throws {
        let snapshot = try CodexRateLimits.parse(Data(#"{"rateLimitsByLimitId":{}}"#.utf8))
        #expect(snapshot.windows.isEmpty)
        #expect(snapshot.state == .partial)
    }
    @Test func claudeKnownOnly() throws {
        let now = Date(timeIntervalSince1970: 1730947200)
        let data = Data(#"{"capturedAt":1730947190,"rate_limits":{"five_hour":{"used_percentage":25,"resets_at":1730957200},"spend_limit":{"used_percentage":90}}}"#.utf8)
        let snapshot = try ClaudeLocalSource.parse(data, now: now)
        #expect(snapshot.windows.count == 1)
        #expect(snapshot.windows[0].availablePercent == 75)
        #expect(snapshot.state == .connected)
        #expect(try ClaudeLocalSource.parse(data, now: now.addingTimeInterval(400)).state == .stale)
    }
    @Test func claudeFutureRejected() {
        #expect(throws: UsageFetchError.invalidResponse) {
            try ClaudeLocalSource.parse(Data(#"{"capturedAt":1730947200,"rate_limits":{}}"#.utf8),
                                       now: Date(timeIntervalSince1970: 1))
        }
    }
}

actor MockTransport: CodexTransport {
    var accountType: String?
    let failure: UsageFetchError?
    init(accountType: String? = "chatgpt", failure: UsageFetchError? = nil) {
        self.accountType = accountType; self.failure = failure
    }
    func request(method: String, parameters: Data?) async throws -> Data {
        if let failure { throw failure }
        if method == "account/read" {
            return Data((accountType.map { "{\"account\":{\"type\":\"\($0)\"}}" } ?? "{\"account\":null}").utf8)
        }
        return Data(#"{"rateLimits":{"primary":{"usedPercent":37.5,"windowDurationMins":300,"resetsAt":1930947200}}}"#.utf8)
    }
    func close() async {}
}

actor MockProvider: UsageProvider {
    nonisolated let id: String
    nonisolated let displayName: String
    let identity: ProviderIdentity
    var count = 0
    let delay: Double
    let error: UsageFetchError?
    init(_ identity: ProviderIdentity, delay: Double = 0, error: UsageFetchError? = nil) {
        self.identity = identity; self.id = identity.id; self.displayName = identity.name
        self.delay = delay; self.error = error
    }
    func checkAvailability() async -> ProviderAvailability { .init(available: true, message: "Mock") }
    func fetchUsage() async throws -> UsageSnapshot {
        count += 1
        try await Task.sleep(for: .seconds(delay))
        if let error { throw error }
        return UsageSnapshot(provider: identity, windows: [
            .init(id: "session", name: "Mock", usedPercent: 37.5, resetAt: .now.addingTimeInterval(3600), durationMinutes: 300)
        ], fetchedAt: .now, source: .officialAppServer, state: .connected)
    }
}

struct ConnectorTests {
    @Test func authenticated() async throws {
        let provider = CodexProvider(transport: MockTransport())
        #expect(try await provider.fetchUsage().windows.first?.availablePercent == 62.5)
    }
    @Test(arguments: ["apiKey", "unknown"])
    func notSubscription(type: String) async {
        await #expect(throws: UsageFetchError.unauthenticated) {
            try await CodexProvider(transport: MockTransport(accountType: type)).fetchUsage()
        }
    }
    @Test func missingAuthentication() async {
        await #expect(throws: UsageFetchError.unauthenticated) {
            try await CodexProvider(transport: MockTransport(accountType: nil)).fetchUsage()
        }
    }
    @Test(arguments: [UsageFetchError.timeout, .http(429, retryAfter: 300), .http(500, retryAfter: nil), .processFailed])
    func failures(error: UsageFetchError) async {
        await #expect(throws: error) { try await CodexProvider(transport: MockTransport(failure: error)).fetchUsage() }
    }
    @Test func missingExecutable() async {
        #expect(CodexProvider.executable(customPath: "/does/not/exist") == nil)
        let transport = CodexAppServer(executable: URL(fileURLWithPath: "/does/not/exist"))
        await #expect(throws: UsageFetchError.processFailed) { try await transport.request(method: "account/read") }
        await transport.close()
    }
    @Test func timeout() async {
        await #expect(throws: UsageFetchError.timeout) {
            try await UsageRefreshCoordinator.fetchWithTimeout(MockProvider(.codex, delay: 10), seconds: 0.01)
        }
    }
    @Test func unavailableProviders() async throws {
        #expect(try await ChatGPTProvider().fetchUsage().windows.isEmpty)
        let claude = ClaudeProvider(file: URL(fileURLWithPath: "/does/not/exist"))
        #expect(try await claude.fetchUsage().state == .unavailable)
    }
}

@Suite(.serialized)
@MainActor struct CoordinatorTests {
    private func coordinator(delay: Double = 0, error: UsageFetchError? = nil) -> (UsageRefreshCoordinator, MockProvider) {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let codex = MockProvider(.codex, delay: delay, error: error)
        let providers: [ProviderIdentity: any UsageProvider] = [
            .chatGPT: MockProvider(.chatGPT), .claude: MockProvider(.claude), .codex: codex
        ]
        return (UsageRefreshCoordinator(preferences: preferences, providers: providers, persistHistory: false), codex)
    }
    // A consulta individual não altera a leitura do outro card.
    @Test func refreshOnlySelectedProvider() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let codex = MockProvider(.codex)
        let claude = MockProvider(.claude)
        let coordinator = UsageRefreshCoordinator(preferences: preferences,
            providers: [.codex: codex, .claude: claude], persistHistory: false)
        await coordinator.refresh()
        let previousCodex = coordinator.snapshots.first { $0.provider == .codex }
        await coordinator.refresh(provider: .claude)
        #expect(await codex.count == 1)
        #expect(await claude.count == 2)
        #expect(coordinator.snapshots.first { $0.provider == .codex }?.fetchedAt == previousCodex?.fetchedAt)
        #expect(coordinator.history.filter { $0.provider == .codex }.count == 1)
    }

    @Test func individualRetryRespectsRetryAfter() async {
        let (coordinator, codex) = coordinator(error: .http(429, retryAfter: 300))
        await coordinator.refresh(provider: .codex)
        await coordinator.refresh(provider: .codex)
        #expect(await codex.count == 1)
    }

    @Test func periodicStops() async {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        let mock = MockProvider(.codex)
        let coordinator = UsageRefreshCoordinator(preferences: preferences,
            providers: [.codex: mock, .claude: MockProvider(.claude), .chatGPT: MockProvider(.chatGPT)],
            persistHistory: false, pollingSecondsOverride: 0.01)
        coordinator.start()
        try? await Task.sleep(for: .milliseconds(100))
        await coordinator.shutdown()
        let count = await mock.count
        #expect(count >= 2)
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await mock.count == count)
    }

    @Test func duplicateRefresh() async {
        let (coordinator, codex) = coordinator(delay: 0.05)
        async let first: Void = coordinator.refresh()
        async let second: Void = coordinator.refresh()
        _ = await (first, second)
        #expect(await codex.count == 1)
        #expect(!coordinator.isRefreshing)
        #expect(coordinator.history.count == 2)
    }
    @Test func backoffAndManual() async {
        let (coordinator, codex) = coordinator(error: .http(500, retryAfter: nil))
        await coordinator.refresh()
        await coordinator.refresh(manual: false)
        #expect(await codex.count == 1)
        await coordinator.refresh(manual: true)
        #expect(await codex.count == 2)
    }
    @Test func retryAfterNotBypassed() async {
        let (coordinator, codex) = coordinator(error: .http(429, retryAfter: 300))
        await coordinator.refresh()
        await coordinator.refresh(manual: true)
        #expect(await codex.count == 1)
    }
    @Test func sleepWake() async {
        let (coordinator, codex) = coordinator()
        coordinator.suspend()
        await coordinator.refresh()
        #expect(await codex.count == 0)
        coordinator.resume()
        try? await Task.sleep(for: .milliseconds(30))
        #expect(await codex.count == 1)
        coordinator.stop()
    }
    @Test func cancellation() async {
        let (coordinator, _) = coordinator(delay: 20)
        let task = Task { await coordinator.refresh() }
        try? await Task.sleep(for: .milliseconds(10))
        task.cancel()
        await task.value
        #expect(!coordinator.isRefreshing)
    }
}

struct PersistenceAndAlertTests {
    @Test func retentionAndDelete() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = HistoryStore(file: directory.appendingPathComponent("history.json"))
        let entries = [Date.now, Date.now.addingTimeInterval(-40 * 86400)].map {
            UsageHistoryEntry(provider: .codex, window: "session", timestamp: $0, usedPercent: 37.5, resetAt: nil, state: .connected)
        }
        #expect(try await store.save(entries, retentionDays: 30).count == 1)
        #expect(await store.read(retentionDays: 30).count == 1)
        try await store.clear()
        #expect(await store.read(retentionDays: 30).isEmpty)
    }
    @Test func thresholdsAndRenewal() {
        #expect(AlertPolicy.crossed(previous: 30, current: 24) == 25)
        #expect(AlertPolicy.crossed(previous: 30, current: 4) == 5)
        #expect(AlertPolicy.crossed(previous: 4, current: 4) == nil)
        #expect(AlertPolicy.crossed(previous: nil, current: 4) == nil)
        let previous = UsageWindow(id: "a", name: "", usedPercent: 90, resetAt: .now.addingTimeInterval(-10), durationMinutes: 300)
        let current = UsageWindow(id: "a", name: "", usedPercent: 10, resetAt: .now.addingTimeInterval(3600), durationMinutes: 300)
        #expect(AlertPolicy.renewed(previous: previous, current: current, now: .now))
        #expect(!AlertPolicy.renewed(previous: previous, current: previous, now: .now))
        #expect(RetryPolicy.delay(failures: 20, interval: 120, error: nil) == 3600)
        #expect(RetryPolicy.delay(failures: 1, interval: 120, error: .http(429, retryAfter: 900)) == 900)
    }
}
