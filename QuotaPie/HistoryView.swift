import SwiftUI
import Charts
import UserNotifications

struct HistoryView: View {
    let coordinator: UsageRefreshCoordinator
    @State private var selected: ProviderIdentity = .codex
    @State private var confirmDeletion = false
    private var entries: [UsageHistoryEntry] {
        Array(coordinator.history.filter { $0.provider == selected && $0.usedPercent != nil }.suffix(2000))
    }
    var body: some View {
        @Bindable var preferences = coordinator.preferences
        VStack(alignment: .leading, spacing: 18) {
            Text("Evolução da utilização").font(.title2.bold())
            Picker("Provedor", selection: $selected) {
                ForEach(ProviderIdentity.supportedProviders) { Text($0.name).tag($0) }
            }.pickerStyle(.segmented)
            if entries.isEmpty {
                ContentUnavailableView("Sem leituras", systemImage: "chart.xyaxis.line",
                                       description: Text("As leituras reais aparecerão aqui após a conexão."))
            } else {
                Chart(entries) { entry in
                    if let used = entry.usedPercent {
                        LineMark(x: .value("Data", entry.timestamp), y: .value("Utilizado", used))
                            .foregroundStyle(by: .value("Janela", entry.window))
                    }
                }.chartYScale(domain: 0...100).chartYAxisLabel("% utilizado").frame(minHeight: 220)
            }
            Picker("Retenção", selection: $preferences.retentionDays) {
                ForEach([7, 30, 90], id: \.self) { Text("\($0) dias").tag($0) }
            }
            Text("Até 2.000 leituras recentes. Janelas distintas têm séries separadas; lacunas não indicam uso zero.").font(.caption).foregroundStyle(.secondary)
            Button("Apagar histórico local", role: .destructive) { confirmDeletion = true }
                .confirmationDialog("Apagar todas as leituras?", isPresented: $confirmDeletion) {
                    Button("Apagar histórico", role: .destructive) { coordinator.clearHistory() }
                }
            if let message = coordinator.statusMessage { Text(message).font(.caption).foregroundStyle(.orange) }
        }.padding(24)
    }
}

struct AlertsSettingsView: View {
    let preferences: AppPreferences
    @State private var message: String?
    var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section("Notificações opcionais") {
                Toggle("Alertar ao cruzar 25%, 10% e 5% disponíveis", isOn: $preferences.alerts)
                Toggle("Alertar após renovação confirmada", isOn: $preferences.renewalAlerts)
                Text("Os alertas dependem de duas leituras reais e recentes. Um horário previsto, isoladamente, não confirma renovação.")
                    .font(.caption).foregroundStyle(.secondary)
                if let message { Text(message).font(.caption) }
            }
        }.formStyle(.grouped)
        .onChange(of: preferences.alerts) { requestIfNeeded() }
        .onChange(of: preferences.renewalAlerts) { requestIfNeeded() }
    }
    private func requestIfNeeded() {
        guard preferences.alerts || preferences.renewalAlerts else { return }
        Task {
            do {
                let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
                message = granted ? "Notificações autorizadas." : "Notificações não autorizadas. Você pode alterar isso nos Ajustes do Sistema."
                if !granted { preferences.alerts = false; preferences.renewalAlerts = false }
            } catch { message = "Não foi possível solicitar notificações."; preferences.alerts = false; preferences.renewalAlerts = false }
        }
    }
}
