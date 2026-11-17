
import SwiftUI

/// Only unambiguous, matching windows belong in the two main rings.
struct UsageRingWindows {
    let session: UsageWindow?
    let weekly: UsageWindow?
    let additional: [UsageWindow]

    init(windows: [UsageWindow]) {
        let sessions = windows.filter { $0.durationMinutes == 300 }
        let weeks = windows.filter { $0.durationMinutes == 10080 }
        let session = sessions.first { $0.id == "five_hour" || $0.id == "codex.primary" }
            ?? (sessions.count == 1 ? sessions.first : nil)
        var weekly = weeks.first { $0.id == "seven_day" || $0.id == "codex.secondary" }
            ?? (weeks.count == 1 && !weeks[0].id.hasPrefix("seven_day_") ? weeks.first : nil)
        if let session, let candidate = weekly,
           let sessionDot = session.id.lastIndex(of: "."),
           let weeklyDot = candidate.id.lastIndex(of: "."),
           session.id[..<sessionDot] != candidate.id[..<weeklyDot] {
            weekly = nil
        }
        self.session = session
        self.weekly = weekly
        self.additional = windows.filter { $0.id != session?.id && $0.id != weekly?.id }
    }
}

enum QuotaStyle {
    static func color(_ value: Double?) -> Color {
        QuotaTone.remaining(value).color
    }

    // Formatação explícita em português, mantendo o fuso local.
    static func date(_ date: Date, today: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "pt_BR")
        formatter.timeZone = .current
        formatter.dateFormat = today ? "H:mm" : "d MMM, H:mm"
        return formatter.string(from: date)
    }

    @MainActor static func renewal(_ reset: Date, now: Date, preferences: AppPreferences) -> String {
        let absolute = date(reset, today: Calendar.current.isDate(reset, inSameDayAs: now))
        if reset <= now {
            return "Renovação pendente de confirmação" + (preferences.absoluteTime ? " · " + absolute : "")
        }
        let countdown = "Renova em " + ProviderCard.remaining(reset, now: now)
        if preferences.countdown {
            return countdown + (preferences.absoluteTime ? " · " + absolute : "")
        }
        return "Renova " + absolute
    }

    static func percentage(_ value: Double?) -> String {
        UsageWindow.validPercent(value).map { $0.formatted(.number.precision(.fractionLength(0...1))) + "%" } ?? "—"
    }
}

// Destaque do saldo da sessão, sem consolidar cotas diferentes.
struct SessionBalanceView: View {
    let available: Double?
    var resetAt: Date? = nil
    var now: Date = .now
    var loading = false

    var body: some View {
        VStack(spacing: 5) {
            if loading {
                ProgressView().controlSize(.small)
            } else if available == 0 {
                Text("Volta em").font(.caption).modifier(MonitorSecondaryText())
                Text(resetAt.map { $0 > now ? ProviderCard.remaining($0, now: now) : "A confirmar" } ?? "Sem previsão")
                    .font(.headline).multilineTextAlignment(.center)
            } else {
                Text(QuotaStyle.percentage(available))
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7).lineLimit(1).monospacedDigit()
                Text("restante").font(.caption)
                Text("na sessão").font(.caption2).modifier(MonitorSecondaryText())
            }
        }
        .padding(10).frame(width: 90, height: 104)
        .background(LinearGradient(colors: [
            QuotaStyle.color(available).opacity(0.12),
            Color.primary.opacity(0.04),
            QuotaStyle.color(available).opacity(0.08)
        ], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20)
            .strokeBorder(QuotaStyle.color(available).opacity(0.3)))
        .accessibilityElement(children: .combine)
    }
}

// A largura da barra acompanha apenas o percentual restante validado.
private struct QuotaBar: View {
    let available: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(available == 0 ? MonitorDesign.red.opacity(0.18) : Color.primary.opacity(0.14))
                if let value = UsageWindow.validPercent(available) {
                    Capsule().fill(QuotaStyle.color(value).gradient)
                        .frame(width: geometry.size.width * value / 100)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: value)
                }
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}

struct QuotaWindowDetails: View {
    let window: UsageWindow?
    let title: String
    let preferences: AppPreferences
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Circle().fill(QuotaStyle.color(window?.availablePercent))
                    .frame(width: 6, height: 6).accessibilityHidden(true)
                Text(title).font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Text(QuotaStyle.percentage(window?.availablePercent))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            QuotaBar(available: window?.availablePercent).padding(.vertical, 3)
            if let window {
                if let reset = window.resetAt {
                    if preferences.absoluteTime || preferences.countdown {
                        Text(QuotaStyle.renewal(reset, now: now, preferences: preferences))
                            .font(.caption2)
                            .foregroundStyle(reset <= now ? MonitorDesign.yellow : MonitorDesign.secondary)
                    }
                } else {
                    Text("Renovação não informada").font(.caption2).modifier(MonitorSecondaryText())
                }
                if window.availablePercent == 0 { Text("Limite atingido").font(.caption2).foregroundStyle(MonitorDesign.red) }
            } else {
                Text("Dados não disponíveis").font(.caption2).modifier(MonitorSecondaryText())
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

struct ProviderUsageSummary: View {
    let windows: [UsageWindow]
    let preferences: AppPreferences
    let now: Date
    @State private var expanded = false

    var body: some View {
        let selection = UsageRingWindows(windows: windows)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                SessionBalanceView(available: selection.session?.availablePercent,
                                   resetAt: selection.session?.resetAt, now: now)
                Rectangle().fill(.primary.opacity(0.14)).frame(width: 1, height: 110)
                VStack(alignment: .leading, spacing: 10) {
                    QuotaWindowDetails(window: selection.session, title: "Sessão", preferences: preferences, now: now)
                    QuotaWindowDetails(window: selection.weekly, title: "Semana", preferences: preferences, now: now)
                }
            }
            if !selection.additional.isEmpty {
                Button("Mais limites (\(selection.additional.count))") { expanded.toggle() }
                    .buttonStyle(.borderless)
                    .popover(isPresented: $expanded) {
                    ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(selection.additional) { window in
                            QuotaWindowDetails(window: window, title: window.name, preferences: preferences, now: now)
                        }
                    }.padding(16)
                    }.frame(width: 300, height: 240)
                }.font(.caption)
            }
        }
    }
}

#if DEBUG
// Os valores fictícios ficam restritos às prévias de desenvolvimento.
private struct QuotaCardPreview: View {
    let remaining: Double
    private let now = Date.now
    private let preferences = AppPreferences(defaults: UserDefaults(suiteName: "AIUsageMonitor.CardPreviews") ?? .standard)

    var body: some View {
        ProviderCard(snapshot: UsageSnapshot(
            provider: .codex,
            windows: [
                UsageWindow(id: "codex.primary", name: "Sessão", usedPercent: 100 - remaining,
                            resetAt: now.addingTimeInterval(88 * 60), durationMinutes: 300),
                UsageWindow(id: "codex.secondary", name: "Semana", usedPercent: 100 - remaining,
                            resetAt: now.addingTimeInterval(5 * 86400 + 23 * 3600), durationMinutes: 10080)
            ],
            fetchedAt: now, source: .demonstration, state: .demonstration
        ), preferences: preferences)
        .padding(16).frame(width: 400).preferredColorScheme(.dark)
    }
}

#Preview("Normal · 83% restante") {
    QuotaCardPreview(remaining: 83)
}

#Preview("Baixo · 15% restante") {
    QuotaCardPreview(remaining: 15)
}

#Preview("Limite atingido · 0% restante") {
    QuotaCardPreview(remaining: 0)
}
#endif
