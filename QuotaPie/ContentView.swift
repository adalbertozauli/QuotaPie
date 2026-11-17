import SwiftUI

struct UsageRingView: View {
    let available: Double?
    var loading = false
    var failed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var value: Double? { UsageWindow.validPercent(available) }
    private var tint: Color { QuotaStyle.color(value) }
    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: 6)
            Circle().trim(from: 0, to: (value ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: value)
            VStack(spacing: 1) {
                if loading { ProgressView().controlSize(.small) }
                else {
                    Text(value.map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—")
                        .font(.system(.title3, design: .rounded, weight: .semibold)).monospacedDigit()
                    Text(failed ? "sem leitura" : "disponível").font(.system(size: 9)).modifier(MonitorSecondaryText())
                }
            }
        }
        .frame(width: 76, height: 76)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(loading ? "Consultando utilização" : value.map { "\($0.formatted()) por cento disponível" } ?? "Dados indisponíveis")
    }
}

struct DashboardView: View {
    let coordinator: UsageRefreshCoordinator
    let settings: () -> Void
    var contentHeightChanged: ((CGFloat) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            MonitorHeader(coordinator: coordinator, settings: settings)
                .modifier(MonitorMeasure(part: "header"))
            ScrollView {
                VStack(spacing: 12) {
                    if !coordinator.preferences.onboardingComplete {
                        OnboardingView(coordinator: coordinator, settings: settings)
                    }
                    ForEach(coordinator.snapshots) { snapshot in
                        ProviderCard(snapshot: snapshot, preferences: coordinator.preferences,
                                     isRefreshing: coordinator.isRefreshing, retry: {
                            Task { await coordinator.refresh(provider: snapshot.provider) }
                        })
                    }
                    // Assinatura original, sem filtros ou recortes; acompanha a rolagem.
                    Image("AdalbertoZauliSymbol")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 112, height: 112)
                        .opacity(0.25)
                        .accessibilityLabel("Logomarca AZ")
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .modifier(MonitorMeasure(part: "cards"))
            }
            .scrollIndicators(.automatic)
            Divider().padding(.horizontal, 14)
            MonitorFooter(coordinator: coordinator)
                .modifier(MonitorMeasure(part: "footer"))
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: .infinity)
        .foregroundStyle(scheme == .dark ? MonitorDesign.text : Color.primary)
        .background(scheme == .dark ? MonitorDesign.background : Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.12)))
        .preferredColorScheme(coordinator.preferences.colorScheme)
        .onPreferenceChange(MonitorHeightKey.self) { sizes in
            guard sizes.count == 3 else { return }
            contentHeightChanged?(sizes.values.reduce(0, +) + 1)
        }
    }
}

private struct MonitorHeader: View {
    let coordinator: UsageRefreshCoordinator
    let settings: () -> Void
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "chart.pie.fill").font(.system(size: 27))
                    .foregroundStyle(MonitorDesign.cyan).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI Usage Monitor").font(.headline)
                    Text("SUAS COTAS, COM CLAREZA")
                        .font(.system(size: 9, weight: .medium)).tracking(0.8)
                        .modifier(MonitorSecondaryText())
                }
                Spacer(minLength: 4)
                MonitorIconButton(symbol: "arrow.clockwise", title: "Atualizar cotas",
                                  busy: coordinator.isRefreshing, disabled: coordinator.isRefreshing) {
                    Task { await coordinator.refresh() }
                }
                MonitorIconButton(symbol: "gearshape", title: "Configurações", action: settings)
                    .accessibilityIdentifier("openSettings")
            }
            HStack {
                Label("Resumo geral", systemImage: "square.3.layers.3d").fontWeight(.semibold)
                Spacer()
                Label("Automático · \(coordinator.preferences.refreshMinutes) min", systemImage: "clock")
            }
            .font(.caption2).modifier(MonitorSecondaryText())
        }.padding(14)
    }
}

private struct MonitorFooter: View {
    let coordinator: UsageRefreshCoordinator
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Text(MonitorStatus.text(
                    coordinator.snapshots.filter { coordinator.preferences.enabled($0.provider) },
                    refreshing: coordinator.isRefreshing, now: context.date,
                    interval: Double(coordinator.preferences.refreshMinutes * 60)))
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if let date = coordinator.lastAttempt {
                    Text(date, style: .time).monospacedDigit().help("Última tentativa de atualização")
                }
                Button("Sair") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
            }
            .font(.caption2).modifier(MonitorSecondaryText()).padding(12)
        }
    }
}

struct ProviderCard: View {
    let snapshot: UsageSnapshot
    let preferences: AppPreferences
    var isRefreshing = false
    var retry: (() -> Void)? = nil
    @State private var showingSource = false
    // Dados preservados após falha devem ficar identificados no cabeçalho.
    private var failedWithCache: Bool {
        !snapshot.windows.isEmpty && (snapshot.state == .cached || snapshot.state == .unauthenticated)
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let old = snapshot.isStale(at: context.date, interval: Double(preferences.refreshMinutes * 60))
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: snapshot.provider.symbol).font(.title3)
                    Text(snapshot.provider.name).font(.headline)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(snapshot.state == .connected && !old ? MonitorDesign.green : Color.secondary)
                            .frame(width: 5, height: 5).accessibilityHidden(true)
                        Text(failedWithCache ? "Em cache · falha ao atualizar" :
                         old && !snapshot.windows.isEmpty ? "Dados antigos" : snapshot.state.label)
                    }
                        .font(.caption2).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.primary.opacity(0.06), in: Capsule())
                    if failedWithCache, let retry {
                        // Reutiliza o coordenador, sem acessar o conector na view.
                        Button(action: retry) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless).controlSize(.small)
                        .disabled(isRefreshing)
                        .help("Tentar novamente")
                        .accessibilityLabel("Tentar atualizar \(snapshot.provider.name) novamente")
                        .accessibilityIdentifier("retry-\(snapshot.provider.id)")
                    }
                }
                if snapshot.windows.isEmpty {
                    HStack(spacing: 16) {
                        SessionBalanceView(available: nil, loading: snapshot.state == .loading)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(snapshot.message ?? "Aguardando primeira consulta.").font(.caption).modifier(MonitorSecondaryText()).fixedSize(horizontal: false, vertical: true)
                            Link("Abrir \(snapshot.provider.name) ↗", destination: snapshot.provider.website).font(.caption)
                        }
                    }
                } else {
                    ProviderUsageSummary(windows: snapshot.windows, preferences: preferences, now: context.date)

                }
                // Informações secundárias abrem à parte, sem aumentar o card.
                HStack {
                    if !snapshot.windows.isEmpty {
                        Text("Leitura: \(QuotaStyle.date(snapshot.fetchedAt))")
                    }
                    Spacer()
                    Button { showingSource.toggle() } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Fonte dos dados de \(snapshot.provider.name)")
                    .popover(isPresented: $showingSource) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Fonte dos dados").font(.headline)
                            Text(snapshot.source.label)
                            if let message = snapshot.message { Text(message) }
                        }
                        .font(.caption).padding(16).frame(width: 280)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }.font(.caption2).modifier(MonitorSecondaryText())
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .modifier(MonitorSurface())
        }
    }
    static func remaining(_ date: Date, now: Date) -> String {
        let minutes = max(0, Int(ceil(date.timeIntervalSince(now) / 60)))
        if minutes >= 1440 { return "\(minutes / 1440)d \((minutes % 1440) / 60)h" }
        return minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)min" : "\(minutes)min"
    }
}

struct OnboardingView: View {
    let coordinator: UsageRefreshCoordinator
    let settings: () -> Void
    @State private var step = 0
    private let titles = ["Bem-vindo", "Suas fontes de dados", "Conecte com segurança", "Teste de consulta", "Tudo pronto"]
    private let messages = [
        "Acompanhe cotas verificáveis diretamente na barra de menus.",
        "Codex usa o App Server. Claude recebe métricas locais do Claude Code.",
        "Entre no Codex pelo CLI. Para Claude, configure a ponte de status line descrita em Configurações.",
        "Consulte as fontes disponíveis. Você pode continuar mesmo sem nenhuma conta conectada.",
        "O ícone da barra mantém suas leituras por perto. Ausência de dados nunca vira um saldo fictício."
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(step + 1)/5 · \(titles[step])").font(.headline)
            Text(messages[step]).font(.caption).modifier(MonitorSecondaryText())
            HStack {
                if step == 2 { Button("Configurar", action: settings) }
                if step == 3 {
                    Button("Testar") { Task { await coordinator.refresh() } }.disabled(coordinator.isRefreshing)
                }
                Spacer()
                Button(step == 4 ? "Concluir" : "Continuar") {
                    if step < 4 { step += 1 } else { coordinator.preferences.onboardingComplete = true }
                }.buttonStyle(.borderedProminent)
            }
        }.padding(14).background(.teal.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
    }
}
