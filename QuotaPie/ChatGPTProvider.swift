import Foundation

struct ChatGPTProvider: UsageProvider {
    let id = "chatGPT"
    let displayName = "ChatGPT"
    func checkAvailability() async -> ProviderAvailability {
        ProviderAvailability(available: false, message: "Não foi localizada uma interface oficial para todas as cotas do chat convencional.")
    }
    func fetchUsage() async throws -> UsageSnapshot {
        UsageSnapshot.empty(.chatGPT, state: .unavailable,
                            message: "Dados de utilização não disponíveis para esta modalidade. Consulte os limites no ChatGPT; cotas do Codex são exibidas separadamente.")
    }
}

#if DEBUG
struct DemonstrationProvider: UsageProvider {
    let provider: ProviderIdentity
    var id: String { provider.id }
    var displayName: String { provider.name }
    func checkAvailability() async -> ProviderAvailability { .init(available: true, message: "Demonstração") }
    func fetchUsage() async throws -> UsageSnapshot {
        if CommandLine.arguments.contains("--ui-empty") {
            return UsageSnapshot(provider: provider, windows: [], fetchedAt: .now, source: .demonstration,
                                 state: .demonstration, message: "Demonstração de dados indisponíveis.")
        }
        return UsageSnapshot(provider: provider, windows: [
            UsageWindow(id: "demo.session", name: "Sessão fictícia", usedPercent: provider == .codex ? 37.5 : 75,
                        resetAt: Date.now.addingTimeInterval(3600), durationMinutes: 300),
            UsageWindow(id: "demo.week", name: "Semana fictícia", usedPercent: 90,
                        resetAt: Date.now.addingTimeInterval(86400), durationMinutes: 10080)
        ], fetchedAt: .now, source: .demonstration, state: .demonstration, message: "Dados fictícios para desenvolvimento.")
    }
}
#endif
