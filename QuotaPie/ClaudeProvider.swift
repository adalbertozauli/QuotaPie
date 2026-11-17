import Foundation

struct ClaudeLocalSource: Sendable {
    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/AIUsageMonitor", isDirectory: true)
    }
    static var file: URL { directory.appendingPathComponent("claude-usage.json") }

    struct Envelope: Decodable {
        struct Window: Decodable {
            let used_percentage: Double?
            let resets_at: Double?
        }
        struct Limits: Decodable {
            let five_hour: Window?
            let seven_day: Window?
        }
        let capturedAt: Double
        let rate_limits: Limits
    }
    static func parse(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              let captured = UsageWindow.date(seconds: envelope.capturedAt),
              captured <= now.addingTimeInterval(60) else { throw UsageFetchError.invalidResponse }
        var windows: [UsageWindow] = []
        for (id, title, duration, window) in [
            ("five_hour", "Sessão · 5 horas", 300, envelope.rate_limits.five_hour),
            ("seven_day", "Semana", 10080, envelope.rate_limits.seven_day)
        ] {
            guard let window else { continue }
            windows.append(UsageWindow(id: id, name: title, usedPercent: window.used_percentage,
                                       resetAt: UsageWindow.date(seconds: window.resets_at), durationMinutes: duration))
        }
        var snapshot = UsageSnapshot(provider: .claude, windows: windows, fetchedAt: captured, source: .localStatusLine,
                                     state: windows.isEmpty ? .unavailable :
                                        windows.contains(where: { $0.usedPercent == nil || $0.resetAt == nil }) ? .partial : .connected,
                                     message: windows.isEmpty
                                        ? "Ponte conectada, mas o Claude Code não forneceu cotas nesta leitura. Elas podem aparecer após uma resposta na sessão do Terminal. Usar apenas o Desktop não atualiza esta fonte."
                                        : "Leitura da sessão Claude Code; atualização depende da atividade nessa sessão.")
        if snapshot.isStale(at: now, interval: 120) { snapshot.state = .stale }
        return snapshot
    }
}

struct ClaudeProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    var file = ClaudeLocalSource.file
    func checkAvailability() async -> ProviderAvailability {
        ProviderAvailability(available: FileManager.default.fileExists(atPath: file.path),
                             message: "Configure a ponte de status line no Claude Code.")
    }
    func fetchUsage() async throws -> UsageSnapshot {
        guard FileManager.default.fileExists(atPath: file.path) else {
            return UsageSnapshot.empty(.claude, state: .unavailable,
                                       message: "Conecte a status line do Claude Code nas configurações. Nenhuma credencial é necessária neste app.")
        }
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard let size = attributes[.size] as? NSNumber, size.intValue <= 65536 else { throw UsageFetchError.invalidResponse }
            return try ClaudeLocalSource.parse(Data(contentsOf: file))
        } catch let error as UsageFetchError { throw error }
        catch { throw UsageFetchError.invalidResponse }
    }
}
