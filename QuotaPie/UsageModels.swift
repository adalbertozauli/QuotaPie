import Foundation

enum ProviderIdentity: String, Codable, Sendable, CaseIterable, Identifiable {
    case chatGPT, codex, claude
    // Keep the legacy identity decodable for existing local history.
    static let supportedProviders: [ProviderIdentity] = [.codex, .claude]
    var id: String { rawValue }
    var name: String {
        switch self { case .chatGPT: "ChatGPT"; case .codex: "Codex"; case .claude: "Claude" }
    }
    var symbol: String {
        switch self { case .chatGPT: "bubble.left.and.bubble.right"; case .codex: "terminal"; case .claude: "sparkle" }
    }
    var website: URL {
        switch self {
        case .chatGPT: URL(string: "https://chatgpt.com")!
        case .codex: URL(string: "https://chatgpt.com/codex/settings/usage")!
        case .claude: URL(string: "https://claude.ai/settings/usage")!
        }
    }
}

enum DataSourceKind: String, Codable, Sendable {
    case officialAppServer, localStatusLine, localClaudeCLI, unavailable, demonstration
    var label: String {
        switch self {
        case .officialAppServer: "Codex App Server · oficial"
        case .localStatusLine: "Claude Code · status line local"
        case .localClaudeCLI: "Claude Code · /usage experimental"
        case .unavailable: "Sem interface programática validada"
        case .demonstration: "DEMONSTRAÇÃO · dados fictícios"
        }
    }
}

enum ProviderConnectionState: String, Codable, Sendable {
    case idle, loading, connected, partial, cached, stale, unavailable, unauthenticated, failed, disabled, demonstration
    var label: String {
        switch self {
        case .idle: "Aguardando"; case .loading: "Consultando"; case .connected: "Atualizado"
        case .partial: "Dados parciais"; case .cached: "Em cache"; case .stale: "Dados antigos"
        case .unavailable: "Indisponível"; case .unauthenticated: "Conecte sua conta"
        case .failed: "Falha na consulta"; case .disabled: "Desativado"; case .demonstration: "Demonstração"
        }
    }
}

struct UsageWindow: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let usedPercent: Double?
    let resetAt: Date?
    let durationMinutes: Int?

    init(id: String, name: String, usedPercent: Double?, resetAt: Date?, durationMinutes: Int?) {
        self.id = id
        self.name = name
        self.usedPercent = Self.validPercent(usedPercent)
        self.resetAt = resetAt
        self.durationMinutes = durationMinutes.flatMap { $0 > 0 ? $0 : nil }
    }
    static func validPercent(_ value: Double?) -> Double? {
        guard let value, value.isFinite, (0...100).contains(value) else { return nil }
        return value
    }
    var availablePercent: Double? { Self.validPercent(usedPercent).map { min(100, max(0, 100 - $0)) } }
    static func date(seconds: Double?) -> Date? {
        guard let seconds, seconds.isFinite, seconds > 0, seconds < 253402300800 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}

struct UsageSnapshot: Codable, Sendable, Identifiable {
    let provider: ProviderIdentity
    var windows: [UsageWindow]
    let fetchedAt: Date
    let source: DataSourceKind
    var state: ProviderConnectionState
    var message: String?
    var id: String { provider.id }

    static func empty(_ provider: ProviderIdentity, state: ProviderConnectionState = .idle, message: String? = nil) -> Self {
        Self(provider: provider, windows: [], fetchedAt: .now, source: .unavailable, state: state, message: message)
    }
    func isStale(at date: Date, interval: TimeInterval) -> Bool {
        date.timeIntervalSince(fetchedAt) > max(interval * 2, 300) ||
        windows.contains { $0.resetAt.map { $0 <= date } ?? false }
    }
}

struct ProviderAvailability: Sendable {
    let available: Bool
    let message: String
}

protocol UsageProvider: Sendable {
    var id: String { get }
    var displayName: String { get }
    func checkAvailability() async -> ProviderAvailability
    func fetchUsage() async throws -> UsageSnapshot
}

enum UsageFetchError: Error, Sendable, Equatable, LocalizedError {
    case notInstalled, unauthenticated, timeout, invalidResponse, processFailed, unavailable
    case claudeNotInstalled, terminalUnavailable, claudeProbeDirectory
    case http(Int, retryAfter: TimeInterval?)
    var errorDescription: String? {
        switch self {
        case .notInstalled: "Codex não encontrado. Instale o CLI ou selecione o executável nas configurações."
        case .unauthenticated: "Autentique-se no CLI do provedor com sua assinatura e tente novamente."
        case .claudeNotInstalled: "Claude Code não encontrado. Instale e autentique o CLI no Terminal."
        case .terminalUnavailable: "O macOS impediu a criação do terminal de consulta. Execute o app instalado fora do ambiente de testes."
        case .claudeProbeDirectory: "A pasta ClaudeProbe não é uma pasta vazia e segura. Verifique Library/Application Support/AIUsageMonitor/ClaudeProbe."
        case .timeout: "A consulta excedeu o tempo limite. Tente novamente."
        case .invalidResponse: "A fonte retornou dados incompatíveis ou incompletos."
        case .processFailed: "O processo local encerrou ou não pôde iniciar."
        case .unavailable: "Dados de utilização não disponíveis para esta modalidade."
        case .http(let code, _): code == 429 ? "Muitas consultas. Aguardando para tentar novamente." : "O serviço está temporariamente indisponível."
        }
    }
}

struct UsageHistoryEntry: Codable, Sendable, Identifiable {
    let provider: ProviderIdentity
    let window: String
    let timestamp: Date
    let usedPercent: Double?
    let resetAt: Date?
    let state: ProviderConnectionState
    var id: String { "\(provider.rawValue)-\(window)-\(timestamp.timeIntervalSince1970)" }
}

struct RetryPolicy: Sendable {
    static func delay(failures: Int, interval: TimeInterval, error: UsageFetchError?) -> TimeInterval {
        let backoff = min(3600, interval * pow(2, Double(min(max(failures, 0), 5))))
        if case .http(429, let retry)? = error { return max(backoff, retry ?? 0) }
        return backoff
    }
}
