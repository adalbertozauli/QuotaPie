import Testing
import SwiftUI
import AppKit
@testable import QuotaPie

struct MonitorDesignTests {
    @Test(arguments: [0.0, 19, 20, 50, 51, 100])
    func thresholds(_ value: Double) {
        let expected: QuotaTone = value < 20 ? .critical : value <= 50 ? .attention : .comfortable
        #expect(QuotaTone.remaining(value) == expected)
        let window = UsageWindow(id: "test", name: "", usedPercent: 100 - value,
                                 resetAt: nil, durationMinutes: 300)
        #expect(window.availablePercent == value)
    }

    @Test func unknownStaysNeutral() {
        for value in [nil, .nan, .infinity, -1, 101] as [Double?] {
            #expect(QuotaTone.remaining(value) == .neutral)
        }
    }

    @Test func footerStates() {
        let now = Date.now
        let good = UsageSnapshot(provider: .codex, windows: [
            .init(id: "test", name: "", usedPercent: 19, resetAt: now.addingTimeInterval(3600), durationMinutes: 300)
        ], fetchedAt: now, source: .officialAppServer, state: .connected)
        #expect(MonitorStatus.text([good], refreshing: false, now: now, interval: 120) == "1 serviço atualizado")
        #expect(MonitorStatus.text([good], refreshing: true, now: now, interval: 120) == "Atualizando serviços…")
        #expect(MonitorStatus.text([.empty(.claude, state: .failed)], refreshing: false, now: now, interval: 120) == "1 serviço indisponível")
        #expect(MonitorStatus.text([.empty(.claude)], refreshing: false, now: now, interval: 120) == "Leituras pendentes ou parciais")
        #expect(MonitorStatus.text([good], refreshing: false, now: now.addingTimeInterval(400), interval: 120) != "1 serviço atualizado")
    }

    // Renderização offline: nenhuma consulta é iniciada por estas views.
    @MainActor @Test func renderStatesAndSizes() throws {
        let preferences = AppPreferences(defaults: UserDefaults(suiteName: UUID().uuidString) ?? .standard)
        preferences.onboardingComplete = true
        preferences.appearance = "dark"
        let coordinator = UsageRefreshCoordinator(preferences: preferences, providers: [:], persistHistory: false)
        let now = Date.now
        let directory = URL(fileURLWithPath: "/private/tmp/aiusage-premium-validation", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for state in ["normal", "zero", "offline", "unknown", "loading", "cache"] {
            let used: Double? = state == "unknown" ? nil : state == "zero" ? 100 : 17
            coordinator.snapshots = ProviderIdentity.supportedProviders.map { id in
                if state == "offline" { return .empty(id, state: .failed, message: "Serviço temporariamente indisponível.") }
                return UsageSnapshot(provider: id, windows: [
                    .init(id: id == .codex ? "codex.primary" : "five_hour", name: "Sessão",
                          usedPercent: used, resetAt: now.addingTimeInterval(5280), durationMinutes: 300),
                    .init(id: id == .codex ? "codex.secondary" : "seven_day", name: "Semana",
                          usedPercent: used == nil ? nil : 65, resetAt: now.addingTimeInterval(180000), durationMinutes: 10080)
                ], fetchedAt: now, source: .demonstration,
                   state: state == "cache" ? .cached : .connected,
                   message: state == "cache" ? "Falha ao atualizar" : nil)
            }
            coordinator.isRefreshing = state == "loading"
            for size in [NSSize(width: 360, height: 440), NSSize(width: 420, height: 570), NSSize(width: 520, height: 700)] {
                let host = NSHostingView(rootView: DashboardView(coordinator: coordinator, settings: {}))
                host.frame = NSRect(origin: .zero, size: size)
                host.layoutSubtreeIfNeeded()
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                let data = try #require(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("\(state)-\(Int(size.width)).png"))
                #expect(host.bounds.width == size.width)
            }
        }
    }
    // Confere os recursos dentro do aplicativo compilado, inclusive o alfa.
    @MainActor @Test func brandingAssetsAndAbout() throws {
        let symbol = try #require(NSImage(named: "AdalbertoZauliSymbol"))
        let glass = try #require(NSImage(named: "AdalbertoZauliGlass"))
        #expect(symbol.size.width == symbol.size.height)
        #expect(glass.size.width == glass.size.height)
        let tiff = try #require(symbol.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        #expect(bitmap.hasAlpha)
        let corner = try #require(bitmap.colorAt(x: 0, y: 0))
        #expect(corner.alphaComponent == 0)
        for width in [360, 580] {
            let host = NSHostingView(rootView: AboutView().preferredColorScheme(.dark))
            host.frame = NSRect(x: 0, y: 0, width: width, height: 600)
            host.layoutSubtreeIfNeeded()
            let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: rep)
            let data = try #require(rep.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/private/tmp/aiusage-about-\(width).png"))
        }
    }

}
