import Foundation
import Observation
import AppKit
import Network
import OSLog

@MainActor @Observable
final class UsageRefreshCoordinator {
    let preferences: AppPreferences
    var snapshots = ProviderIdentity.supportedProviders.map { UsageSnapshot.empty($0) }
    var isRefreshing = false
    var lastAttempt: Date?
    var history: [UsageHistoryEntry] = []
    var statusMessage: String?
    private var loop: Task<Void, Never>?
    private var active: Task<Void, Never>?
    private var server: CodexAppServer?
    private var serverPath: URL?
    private var failures: [ProviderIdentity: Int] = [:]
    private var retryAt: [ProviderIdentity: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    private var network: NWPathMonitor?
    private var asleep = false
    private let historyStore: HistoryStore?
    private let suppliedProviders: [ProviderIdentity: any UsageProvider]?
    private let pollingSecondsOverride: Double?
    private let notifications = UsageNotifications()
    private let logger = Logger(subsystem: "AIUsageMonitor", category: "refresh")

    init(preferences: AppPreferences, providers: [ProviderIdentity: any UsageProvider]? = nil, persistHistory: Bool = true, pollingSecondsOverride: Double? = nil) {
        self.preferences = preferences
        self.suppliedProviders = providers
        self.pollingSecondsOverride = pollingSecondsOverride
        self.historyStore = persistHistory ? HistoryStore() : nil
    }

    func start() {
        guard loop == nil else { return }
        if observers.isEmpty && suppliedProviders == nil {
            let center = NSWorkspace.shared.notificationCenter
            observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            })
            observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.resume() }
            })
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { [weak self] path in
                guard path.status == .satisfied else { return }
                Task { @MainActor in
                    guard let self, !self.asleep else { return }
                    await self.refresh(manual: false)
                }
            }
            monitor.start(queue: DispatchQueue(label: "AIUsageMonitor.network"))
            network = monitor
        }
        loop = Task { [weak self] in
            guard let self else { return }
            if let historyStore {
                self.history = await historyStore.read(retentionDays: self.preferences.retentionDays)
            }
            while !Task.isCancelled {
                if !self.asleep { await self.refresh(manual: false) }
                do { try await Task.sleep(for: .seconds(self.pollingSecondsOverride ?? Double(max(60, self.preferences.refreshMinutes * 60)))) }
                catch { break }
            }
        }
    }

    func restartSchedule() {
        loop?.cancel()
        loop = nil
        start()
    }

    func suspend() {
        asleep = true
        active?.cancel()
        let current = server
        Task { await current?.close() }
    }
    func resume() {
        asleep = false
        retryAt.removeAll()
        Task { await refresh(manual: false) }
    }
    func stop() {
        loop?.cancel(); loop = nil
        active?.cancel()
        network?.cancel(); network = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll()
        let current = server
        Task { await current?.close() }
    }

    // Sem filtro, a atualização continua consultando todos os provedores.
    func refresh(manual: Bool = true, provider: ProviderIdentity? = nil) async {
        guard active == nil, !asleep else { return }
        let task = Task { await self.performRefresh(manual: manual, provider: provider) }
        active = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        active = nil
    }

    private func performRefresh(manual: Bool, provider: ProviderIdentity?) async {
        isRefreshing = true
        defer { isRefreshing = false }
        lastAttempt = .now
        var jobs: [(ProviderIdentity, any UsageProvider)] = []
        for id in ProviderIdentity.supportedProviders {
            // O botão do card consulta somente o provedor selecionado.
            if let provider, id != provider { continue }
            guard preferences.enabled(id) else {
                replace(.empty(id, state: .disabled, message: "Provedor desativado."))
                if id == .codex { await server?.close(); server = nil; serverPath = nil }
                continue
            }
            if let date = retryAt[id], date > .now {
                // Manual refresh may bypass ordinary backoff, never an explicit Retry-After.
                if !manual || failures[id, default: 0] < 0 { continue }
            }
            #if DEBUG
            if preferences.demonstration { jobs.append((id, DemonstrationProvider(provider: id))); continue }
            #endif
            if let suppliedProviders, let provider = suppliedProviders[id] {
                jobs.append((id, provider)); continue
            }
            switch id {
            case .chatGPT: jobs.append((id, ChatGPTProvider()))
            case .claude:
                jobs.append((id, preferences.claudeInteractive ? ClaudeCLIProvider() as any UsageProvider : ClaudeProvider()))
            case .codex:
                guard let executable = CodexProvider.executable(customPath: preferences.codexPath) else {
                    recordFailure(id, error: .notInstalled)
                    continue
                }
                if serverPath != executable || server == nil {
                    await server?.close()
                    server = CodexAppServer(executable: executable) { [weak self] data in
                        Task { @MainActor in self?.acceptNotification(data) }
                    }
                    serverPath = executable
                }
                if let server { jobs.append((id, CodexProvider(transport: server))) }
            }
            if let index = snapshots.firstIndex(where: { $0.provider == id }), snapshots[index].windows.isEmpty {
                snapshots[index].state = .loading
            }
        }
        await withTaskGroup(of: (ProviderIdentity, Result<UsageSnapshot, UsageFetchError>).self) { group in
            for (id, provider) in jobs {
                group.addTask {
                    do {
                        let snapshot = try await Self.fetchWithTimeout(provider)
                        return (id, .success(snapshot))
                    } catch is CancellationError {
                        return (id, .failure(.timeout))
                    } catch {
                        return (id, .failure((error as? UsageFetchError) ?? .unavailable))
                    }
                }
            }
            for await (id, result) in group {
                guard !Task.isCancelled else { group.cancelAll(); break }
                switch result {
                case .success(let snapshot):
                    let previous = snapshots.first { $0.provider == id }
                    replace(snapshot)
                    failures[id] = 0
                    retryAt[id] = nil
                    if snapshot.source != .demonstration {
                        await notifications.evaluate(snapshot, previous: previous, enabled: preferences.alerts,
                                                     renewal: preferences.renewalAlerts)
                        appendHistory(snapshot)
                    }
                case .failure(let error): recordFailure(id, error: error)
                }
            }
        }
        if Task.isCancelled {
            for index in snapshots.indices where snapshots[index].state == .loading {
                snapshots[index].state = .idle
            }
            return
        }
        if let historyStore {
            do {
                history = try await historyStore.save(history, retentionDays: preferences.retentionDays)
            } catch { statusMessage = "Não foi possível salvar o histórico local." }
        }
        logger.info("Refresh completed. No account or credential data logged.")
    }

    nonisolated static func fetchWithTimeout(_ provider: any UsageProvider, seconds: Double = 20) async throws -> UsageSnapshot {
        try await withThrowingTaskGroup(of: UsageSnapshot.self) { group in
            group.addTask { try await provider.fetchUsage() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw UsageFetchError.timeout
            }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw UsageFetchError.unavailable }
            return result
        }
    }

    private func acceptNotification(_ data: Data) {
        guard !asleep, preferences.enabled(.codex), let snapshot = try? CodexRateLimits.parse(data) else { return }
        #if DEBUG
        guard !preferences.demonstration else { return }
        #endif
        replace(snapshot)
        appendHistory(snapshot)
    }

    func shutdown() async {
        stop()
        await active?.value
        await server?.close()
    }

    private func replace(_ snapshot: UsageSnapshot) {
        if let index = snapshots.firstIndex(where: { $0.provider == snapshot.provider }) { snapshots[index] = snapshot }
    }
    private func recordFailure(_ id: ProviderIdentity, error: UsageFetchError) {
        let count = abs(failures[id, default: 0]) + 1
        failures[id] = count
        if case .http(429, _) = error { failures[id] = -count }
        retryAt[id] = Date.now.addingTimeInterval(RetryPolicy.delay(failures: count, interval: Double(preferences.refreshMinutes * 60), error: error))
        if var prior = snapshots.first(where: { $0.provider == id }), !prior.windows.isEmpty, prior.source != .demonstration {
            prior.state = error == .unauthenticated ? .unauthenticated : .cached
            prior.message = error.errorDescription
            replace(prior)
        } else {
            replace(.empty(id, state: error == .unauthenticated ? .unauthenticated : .failed, message: error.errorDescription))
        }
        history.append(.init(provider: id, window: "query", timestamp: .now, usedPercent: nil, resetAt: nil,
                             state: error == .unauthenticated ? .unauthenticated : .failed))
    }
    private func appendHistory(_ snapshot: UsageSnapshot) {
        for window in snapshot.windows {
            guard !history.contains(where: { $0.provider == snapshot.provider && $0.window == window.id && $0.timestamp == snapshot.fetchedAt }) else { continue }
            history.append(.init(provider: snapshot.provider, window: window.id, timestamp: snapshot.fetchedAt,
                                 usedPercent: window.usedPercent, resetAt: window.resetAt, state: snapshot.state))
        }
    }
    func clearHistory() {
        let pending = active
        pending?.cancel()
        Task {
            await pending?.value
            history = []
            do { try await historyStore?.clear() }
            catch { statusMessage = "Não foi possível apagar o histórico." }
        }
    }
}
