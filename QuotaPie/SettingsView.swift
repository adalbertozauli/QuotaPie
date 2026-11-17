import SwiftUI
import ServiceManagement

struct SettingsView: View {
    let coordinator: UsageRefreshCoordinator
    @State private var message: String?
    var body: some View {
        @Bindable var preferences = coordinator.preferences
        TabView {
            Form {
                Section("Comportamento") {
                    Toggle("Abrir ao passar o mouse", isOn: $preferences.hover)
                    Toggle("Abrir ao clicar", isOn: $preferences.click)
                    Picker("Atualizar a cada", selection: $preferences.refreshMinutes) {
                        ForEach([1, 2, 5, 10, 15], id: \.self) { Text("\($0) minutos").tag($0) }
                    }
                    Toggle("Exibir horário de renovação", isOn: $preferences.absoluteTime)
                    Toggle("Exibir contagem regressiva", isOn: $preferences.countdown)
                    Text("Datas, fuso e formato de horário seguem o macOS.").font(.caption).foregroundStyle(.secondary)
                    Picker("Aparência", selection: $preferences.appearance) {
                        Text("Sistema").tag("system"); Text("Clara").tag("light"); Text("Escura").tag("dark")
                    }
                    Button(SMAppService.mainApp.status == .enabled ? "Desativar início com macOS" : "Iniciar com macOS") {
                        do {
                            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
                            else { try SMAppService.mainApp.register() }
                            message = "Preferência de início atualizada. Verifique Itens de Início no macOS se houver aprovação pendente."
                        } catch { message = "Não foi possível alterar o início automático. Instale o app em Aplicativos e tente novamente." }
                    }
                }
                #if DEBUG
                Section("Desenvolvimento") {
                    Toggle("Demonstração · dados fictícios", isOn: $preferences.demonstration)
                        .onChange(of: preferences.demonstration) { Task { await coordinator.refresh() } }
                }
                #endif
                if let message { Text(message).font(.caption) }
            }.formStyle(.grouped).tabItem { Label("Geral", systemImage: "gearshape") }

            Form {
                ForEach(ProviderIdentity.supportedProviders) { provider in
                    Section(provider.name) {
                        Toggle("Ativado", isOn: Binding(get: { preferences.enabled(provider) }, set: { preferences.setEnabled(provider, $0); Task { await coordinator.refresh() } }))
                        if let snapshot = coordinator.snapshots.first(where: { $0.provider == provider }) {
                            Text(snapshot.source.label).font(.caption)
                            Text(snapshot.message ?? snapshot.state.label).font(.caption).foregroundStyle(.secondary)
                            if !snapshot.windows.isEmpty { Text("Última leitura: \(snapshot.fetchedAt.formatted())").font(.caption) }
                        }
                        if provider == .codex {
                            TextField("Caminho opcional do executável codex", text: $preferences.codexPath)
                            Text("Autentique com codex login no Terminal. Não use uma chave de API para representar cotas ChatGPT.").font(.caption)
                        }
                        if provider == .claude {
                            Toggle("Consultar /usage pelo Claude Code (experimental)", isOn: $preferences.claudeInteractive)
                                .disabled(coordinator.isRefreshing)
                                .onChange(of: preferences.claudeInteractive) { Task { await coordinator.refresh() } }
                            Text("Abre um terminal de consulta temporário em pasta própria e vazia, sem enviar conversas. A autenticação permanece no Claude Code. A leitura textual pode deixar de funcionar após atualizações do CLI. Requer Claude Code 2.1.311 ou compatível.").font(.caption)
                            if !preferences.claudeInteractive {
                            Text("No arquivo ~/.claude/settings.json, configure statusLine com type command e o comando abaixo. Preserve sua configuração atual se já existir.").font(.caption)
                            Text("\"\(Bundle.main.executablePath ?? "")\" --claude-statusline")
                                .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text("Depois de uma resposta na sessão Claude Code, clique em Verificar conexões. Somente percentuais e horários são armazenados.").font(.caption)
                            Link("Documentação oficial", destination: URL(string: "https://code.claude.com/docs/en/statusline")!)
                            }
                        }
                        Link("Abrir serviço", destination: provider.website)
                    }
                }
                Button("Verificar conexões") { Task { await coordinator.refresh() } }.disabled(coordinator.isRefreshing)
            }.formStyle(.grouped).tabItem { Label("Provedores", systemImage: "network") }

            AlertsSettingsView(preferences: preferences).tabItem { Label("Alertas", systemImage: "bell") }
            HistoryView(coordinator: coordinator).tabItem { Label("Histórico", systemImage: "chart.xyaxis.line") }

            AboutView().tabItem { Label("Sobre", systemImage: "info.circle") }
        }
        .frame(minWidth: 580, minHeight: 560)
        .preferredColorScheme(preferences.colorScheme)
        .onChange(of: preferences.refreshMinutes) { coordinator.restartSchedule() }
    }
}

// A marca completa mantém a iluminação e a proporção do arquivo original.
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let number = info["CFBundleShortVersionString"] as? String
        let build = info["CFBundleVersion"] as? String
        return [number, build.map { "build \($0)" }].compactMap { $0 }.joined(separator: " · ")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image("AdalbertoZauliGlass")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 180)
                    .accessibilityLabel("Logomarca AZ com acabamento Liquid Glass")
                Text("AI Usage Monitor").font(.title.bold())
                if !version.isEmpty { Text("Versão \(version)").foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Privacidade por padrão").font(.headline)
                    Text("Sem telemetria, servidores próprios ou coleta de cookies. As credenciais permanecem com os aplicativos dos provedores. Histórico contém apenas métricas.")
                    Text("Fontes: Codex App Server; Claude Code status line ou leitura experimental de /usage.")
                    Text("Implementação nativa, sem componentes externos. CodexBar (MIT) consultado como referência; nenhum código incorporado.").font(.caption).foregroundStyle(.secondary)
                    Link("Documentação Codex App Server", destination: URL(string: "https://learn.chatgpt.com/docs/app-server")!)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
    }
}
