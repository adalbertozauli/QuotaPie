import SwiftUI

// Paleta única. No modo claro, os textos usam cores nativas para manter contraste.
enum MonitorDesign {
    static func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    static let background = rgb(0x242833)
    static let card = rgb(0x303642)
    static let elevated = rgb(0x3B424F)
    static let text = rgb(0xE8EAF0)
    static let secondary = rgb(0xA7ADBA)
    static let cyan = rgb(0x39C8EF)
    static let turquoise = rgb(0x35C5B2)
    static let green = rgb(0x32D375)
    static let yellow = rgb(0xFFCF24)
    static let red = rgb(0xFF6673)
}

// Faixas de apresentação: não altera nem arredonda o saldo recebido.
enum QuotaTone: Equatable {
    case neutral, comfortable, attention, critical
    static func remaining(_ value: Double?) -> Self {
        guard let value = UsageWindow.validPercent(value) else { return .neutral }
        return value > 50 ? .comfortable : value >= 20 ? .attention : .critical
    }
    var color: Color {
        switch self {
        case .neutral: .secondary
        case .comfortable: MonitorDesign.green
        case .attention: MonitorDesign.yellow
        case .critical: MonitorDesign.red
        }
    }
}

struct MonitorSurface: ViewModifier {
    var elevated = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var opaque
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 16)
                    .fill(scheme == .dark ? (elevated ? MonitorDesign.elevated : MonitorDesign.card)
                          : Color(nsColor: .controlBackgroundColor))
                    .opacity(opaque ? 1 : 0.96)
            }
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.primary.opacity(contrast == .increased ? 0.4 : 0.1)))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

struct MonitorSecondaryText: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        content.foregroundStyle(contrast == .increased ? Color.primary :
            scheme == .dark ? MonitorDesign.secondary : Color.secondary)
    }
}

struct MonitorControlStyle: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var opaque
    func body(content: Content) -> some View {
        // O estilo nativo fornece estados pressionado, desabilitado e foco.
        if #available(macOS 26.0, *), !opaque {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
    }
}

struct MonitorIconButton: View {
    let symbol: String
    let title: String
    var busy = false
    var disabled = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action: action) {
            ZStack {
                Image(systemName: symbol).opacity(busy ? 0 : 1)
                if busy { ProgressView().controlSize(.small) }
            }.frame(width: 22, height: 22)
        }
        .modifier(MonitorControlStyle())
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(MonitorDesign.cyan.opacity(hovered && !disabled ? 0.4 : 0)))
        .onHover { hovered = $0 }
        .disabled(disabled)
        .accessibilityLabel(title).help(title)
    }
}

enum MonitorStatus {
    static func text(_ snapshots: [UsageSnapshot], refreshing: Bool, now: Date, interval: Double) -> String {
        if refreshing { return "Atualizando serviços…" }
        let active = snapshots.filter { $0.state != .disabled }
        if active.isEmpty { return "Nenhum serviço ativo" }
        let unavailable = active.filter { [.failed, .unavailable, .unauthenticated].contains($0.state) }.count
        if unavailable > 0 { return unavailable == 1 ? "1 serviço indisponível" : "\(unavailable) serviços indisponíveis" }
        let fresh = active.filter { $0.state == .connected && !$0.isStale(at: now, interval: interval) }.count
        if fresh == active.count { return fresh == 1 ? "1 serviço atualizado" : "\(fresh) serviços atualizados" }
        if active.contains(where: { $0.state == .demonstration }) { return "Modo demonstrativo" }
        return "Leituras pendentes ou parciais"
    }
}

// Mede o conteúdo natural, independentemente da altura disponível para rolagem.
struct MonitorHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] { [:] }
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
struct MonitorMeasure: ViewModifier {
    let part: String
    func body(content: Content) -> some View {
        content.background(GeometryReader { geometry in
            Color.clear.preference(key: MonitorHeightKey.self, value: [part: geometry.size.height])
        })
    }
}
