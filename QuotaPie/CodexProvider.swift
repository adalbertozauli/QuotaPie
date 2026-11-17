import Foundation

protocol CodexTransport: Sendable {
    func request(method: String, parameters: Data?) async throws -> Data
    func close() async
}

actor CodexAppServer: CodexTransport {
    private let executable: URL
    private let requestTimeout: Double
    private let onUpdate: (@Sendable (Data) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var buffer = Data()
    private var nextID = 0
    private var generation = UUID()
    private var pending: [Int: CheckedContinuation<Data, Error>] = [:]
    private var timeouts: [Int: Task<Void, Never>] = [:]
    private var initialized = false
    private var initialization: Task<Void, Error>?
    private(set) var latestNotification: Data?

    init(executable: URL, requestTimeout: Double = 15, onUpdate: (@Sendable (Data) -> Void)? = nil) {
        self.executable = executable
        self.requestTimeout = requestTimeout
        self.onUpdate = onUpdate
    }

    func request(method: String, parameters: Data? = nil) async throws -> Data {
        try Task.checkCancellation()
        if !initialized {
            if let initialization { try await initialization.value }
            else {
                let task = Task { try await self.initialize() }
                initialization = task
                do { try await task.value; initialization = nil }
                catch { initialization = nil; close(); throw error }
            }
        }
        return try await send(method: method, parameters: parameters)
    }

    private func initialize() async throws {
        let process = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        let session = UUID()
        generation = session
        process.executableURL = executable
        process.arguments = ["app-server"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        // Never substitute an inherited API key for a subscription session.
        environment.removeValue(forKey: "OPENAI_API_KEY")
        environment.removeValue(forKey: "CODEX_API_KEY")
        process.environment = environment
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        output = stdout.fileHandleForReading
        input = stdin.fileHandleForWriting
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            Task { await self?.receive(data, generation: session) }
        }
        process.terminationHandler = { [weak self] _ in
            Task { await self?.ended(generation: session) }
        }
        self.process = process
        do { try process.run() } catch { throw UsageFetchError.processFailed }
        let params = Data(#"{"clientInfo":{"name":"ai_usage_monitor","title":"AI Usage Monitor","version":"1.0"}}"#.utf8)
        _ = try await send(method: "initialize", parameters: params)
        try write(["method": "initialized"])
        initialized = true
    }

    private func send(method: String, parameters: Data?) async throws -> Data {
        guard process?.isRunning == true else { throw UsageFetchError.processFailed }
        nextID += 1
        let id = nextID
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                timeouts[id] = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(self?.requestTimeout ?? 15)) } catch { return }
                    await self?.fail(id: id, error: UsageFetchError.timeout)
                }
                do {
                    var object: [String: Any] = ["method": method, "id": id]
                    if let parameters { object["params"] = try JSONSerialization.jsonObject(with: parameters) }
                    try write(object)
                } catch { fail(id: id, error: UsageFetchError.processFailed) }
            }
        } onCancel: {
            Task { await self.fail(id: id, error: CancellationError()) }
        }
    }

    private func write(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object)
        data.append(10)
        guard let input else { throw UsageFetchError.processFailed }
        try input.write(contentsOf: data)
    }

    private func receive(_ data: Data, generation: UUID) {
        guard generation == self.generation else { return }
        guard !data.isEmpty else { ended(generation: generation); return }
        buffer.append(data)
        guard buffer.count <= 2_000_000 else { close(); return }
        while let newline = buffer.firstIndex(of: 10) {
            let line = Data(buffer[..<newline])
            buffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                close(); return
            }
            if let id = object["id"] as? Int, let continuation = pending.removeValue(forKey: id) {
                timeouts.removeValue(forKey: id)?.cancel()
                if let error = object["error"] as? [String: Any] {
                    let code = error["code"] as? Int
                    let message = (error["message"] as? String ?? "").lowercased()
                    // Classify upstream failures, but never expose raw messages or credentials.
                    if code == 401 || message.contains("unauthorized") || message.contains("not logged") || message.contains("authentication") {
                        continuation.resume(throwing: UsageFetchError.unauthenticated)
                    } else if code == 429 {
                        continuation.resume(throwing: UsageFetchError.http(429, retryAfter: nil))
                    } else { continuation.resume(throwing: UsageFetchError.unavailable) }
                } else if let result = object["result"],
                          JSONSerialization.isValidJSONObject(result),
                          let data = try? JSONSerialization.data(withJSONObject: result) {
                    continuation.resume(returning: data)
                } else { continuation.resume(throwing: UsageFetchError.invalidResponse) }
            } else if object["method"] as? String == "account/rateLimits/updated",
                      let params = object["params"], JSONSerialization.isValidJSONObject(params) {
                latestNotification = try? JSONSerialization.data(withJSONObject: params)
                if let latestNotification { onUpdate?(latestNotification) }
            }
        }
    }

    private func fail(id: Int, error: Error) {
        timeouts.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(throwing: error)
    }
    private func ended(generation: UUID) {
        guard generation == self.generation else { return }
        close()
    }
    func close() {
        generation = UUID()
        initialized = false
        initialization?.cancel()
        initialization = nil
        output?.readabilityHandler = nil
        process?.terminationHandler = nil
        try? input?.close()
        try? output?.close()
        if let process, process.isRunning { process.terminate() }
        process = nil
        input = nil
        output = nil
        buffer.removeAll()
        latestNotification = nil
        for id in Array(pending.keys) { fail(id: id, error: UsageFetchError.processFailed) }
    }
}

struct CodexRateLimits: Decodable, Sendable {
    struct Window: Decodable, Sendable {
        let usedPercent: Double?
        let windowDurationMins: Int?
        let resetsAt: Double?
    }
    struct Bucket: Decodable, Sendable {
        let limitId: String?
        let limitName: String?
        let primary: Window?
        let secondary: Window?
    }
    let rateLimits: Bucket?
    let rateLimitsByLimitId: [String: Bucket]?

    static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        let decoded: Self
        do { decoded = try JSONDecoder().decode(Self.self, from: data) }
        catch { throw UsageFetchError.invalidResponse }
        guard decoded.rateLimits != nil || decoded.rateLimitsByLimitId != nil else { throw UsageFetchError.invalidResponse }
        var buckets = decoded.rateLimitsByLimitId ?? [:]
        if buckets.isEmpty, let fallback = decoded.rateLimits { buckets[fallback.limitId ?? "codex"] = fallback }
        var windows: [UsageWindow] = []
        for key in buckets.keys.sorted() {
            guard let bucket = buckets[key] else { continue }
            for (kind, candidate) in [("primary", bucket.primary), ("secondary", bucket.secondary)] {
                guard let value = candidate else { continue }
                let duration = value.windowDurationMins
                let title = duration == 10080 ? "Semana" : duration == 300 ? "Sessão · 5 horas" :
                    duration.map { "Janela · \($0) min" } ?? (kind == "primary" ? "Janela principal" : "Janela adicional")
                windows.append(UsageWindow(id: "\(key).\(kind)", name: "\(bucket.limitName ?? key) · \(title)",
                                           usedPercent: value.usedPercent, resetAt: UsageWindow.date(seconds: value.resetsAt),
                                           durationMinutes: duration))
            }
        }
        let partial = windows.isEmpty || windows.contains { $0.usedPercent == nil || $0.resetAt == nil }
        return UsageSnapshot(provider: .codex, windows: windows, fetchedAt: now, source: .officialAppServer,
                             state: partial ? .partial : .connected,
                             message: windows.isEmpty ? "A conta não retornou janelas de utilização." : nil)
    }
}

struct CodexProvider: UsageProvider {
    let id = "codex"
    let displayName = "Codex"
    let transport: any CodexTransport

    static func executable(customPath: String) -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = customPath.isEmpty ? [
            "/opt/homebrew/bin/codex", "/usr/local/bin/codex", home + "/.local/bin/codex",
            "/Applications/Codex.app/Contents/Resources/codex"
        ] : [customPath]
        return paths.first(where: { $0.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: $0) }).map(URL.init(fileURLWithPath:))
    }
    func checkAvailability() async -> ProviderAvailability {
        do {
            _ = try await account()
            return ProviderAvailability(available: true, message: "Conta ChatGPT autenticada no Codex.")
        } catch { return ProviderAvailability(available: false, message: (error as? UsageFetchError)?.errorDescription ?? "Consulta indisponível.") }
    }
    private func account() async throws -> Data {
        let data = try await transport.request(method: "account/read", parameters: Data(#"{"refreshToken":false}"#.utf8))
        struct AccountResponse: Decodable { struct Account: Decodable { let type: String }; let account: Account? }
        guard let response = try? JSONDecoder().decode(AccountResponse.self, from: data) else { throw UsageFetchError.invalidResponse }
        guard let type = response.account?.type, type == "chatgpt" || type == "chatgptAuthTokens" else { throw UsageFetchError.unauthenticated }
        return data
    }
    func fetchUsage() async throws -> UsageSnapshot {
        _ = try await account()
        let data = try await transport.request(method: "account/rateLimits/read", parameters: nil)
        return try CodexRateLimits.parse(data)
    }
}
