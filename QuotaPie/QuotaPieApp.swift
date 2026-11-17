import SwiftUI
import AppKit

@main
enum MonitorLauncher {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--claude-statusline") { exit(ClaudeBridge.capture()) }
        #if DEBUG
        if CommandLine.arguments.contains("--diagnose-claude") {
            Task {
                do {
                    let snapshot = try await ClaudeCLIProvider().fetchUsage()
                    print("Claude: \(snapshot.state.rawValue); janelas=\(snapshot.windows.count)")
                } catch {
                    print("Claude: \((error as? UsageFetchError)?.errorDescription ?? "Consulta cancelada.")")
                }
                exit(0)
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--diagnose-codex") {
            Task {
                guard let url = CodexProvider.executable(customPath: "") else {
                    print("Codex: executável não encontrado nos caminhos suportados.")
                    exit(2)
                }
                let server = CodexAppServer(executable: url)
                do {
                    let snapshot = try await CodexProvider(transport: server).fetchUsage()
                    print("Codex: \(snapshot.state.rawValue); janelas=\(snapshot.windows.count)")
                } catch { print("Codex: \((error as? UsageFetchError)?.errorDescription ?? "Consulta indisponível.")") }
                await server.close()
                exit(0)
            }
            dispatchMain()
        }
        #endif
        QuotaPieApp.main()
    }
}

struct QuotaPieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        Settings { SettingsView(coordinator: AppEnvironment.shared.coordinator) }
    }
}

@MainActor
final class HoverRegion: NSView {
    var entered: (() -> Void)?
    var exited: (() -> Void)?
    private var area: NSTrackingArea?
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let next = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                 owner: self, userInfo: nil)
        addTrackingArea(next)
        area = next
    }
    override func mouseEntered(with event: NSEvent) { entered?() }
    override func mouseExited(with event: NSEvent) { exited?() }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var item: NSStatusItem?
    private var panel: NSPanel?
    private var preferredPanelHeight: CGFloat = 520
    private var settingsWindow: NSWindow?
    private var closeTask: Task<Void, Never>?
    private var buttonInside = false
    private var panelInside = false
    private var openedByClick = false
    private let environment = AppEnvironment.shared

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard NSClassFromString("XCTestCase") == nil else { return }
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.item = item
        if let button = item.button {
            let image = NSImage(systemSymbolName: "chart.pie", accessibilityDescription: "AI Usage Monitor")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(togglePanel)
            button.toolTip = "AI Usage Monitor"
            button.setAccessibilityIdentifier("usageStatusItem")
            let tracking = HoverRegion(frame: button.bounds)
            tracking.autoresizingMask = [.width, .height]
            tracking.entered = { [weak self] in
                guard let self else { return }
                self.buttonInside = true
                self.closeTask?.cancel()
                if self.environment.preferences.hover { self.showPanel() }
            }
            tracking.exited = { [weak self] in self?.buttonInside = false; self?.scheduleClose() }
            button.addSubview(tracking)
        }
        environment.coordinator.start()
    }

    @objc private func togglePanel() {
        guard environment.preferences.click else { return }
        if panel?.isVisible == true && openedByClick {
            panel?.orderOut(nil)
            openedByClick = false
        } else {
            openedByClick = true
            showPanel()
        }
    }

    private func showPanel() {
        guard item?.button?.window != nil else { return }
        if panel == nil {
            let host = NSHostingView(rootView: DashboardView(
                coordinator: environment.coordinator,
                settings: { [weak self] in self?.showSettings() },
                contentHeightChanged: { [weak self] height in
                    // Atualiza o painel fora da passagem de layout do SwiftUI.
                    Task { @MainActor [weak self] in
                        guard let self, abs(self.preferredPanelHeight - height) > 1 else { return }
                        self.preferredPanelHeight = height
                        if self.panel?.isVisible == true { self.positionPanel() }
                    }
                }))
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: preferredPanelHeight),
                                styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
                                backing: .buffered, defer: false)
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = true
            panel.hidesOnDeactivate = false
            panel.level = .popUpMenu
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.contentView = host
            host.wantsLayer = true
            host.layer?.cornerRadius = 18
            host.layer?.masksToBounds = true
            let tracking = HoverRegion(frame: host.bounds)
            tracking.autoresizingMask = [.width, .height]
            tracking.entered = { [weak self] in self?.panelInside = true; self?.closeTask?.cancel() }
            tracking.exited = { [weak self] in self?.panelInside = false; self?.scheduleClose() }
            host.addSubview(tracking)
            self.panel = panel
        }
        positionPanel()
        panel?.orderFrontRegardless()
    }

    private func positionPanel() {
        guard let panel, let button = item?.button, let window = button.window else { return }
        let anchor = window.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? anchor
        let width = min(420, screen.width - 16)
        let height = min(preferredPanelHeight, screen.height - 16)
        let x = min(max(anchor.midX - width / 2, screen.minX + 8), screen.maxX - width - 8)
        panel.setFrame(NSRect(x: x, y: max(screen.minY + 8, anchor.minY - height - 5),
                              width: width, height: height), display: true)
    }

    private func scheduleClose() {
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self, !self.buttonInside, !self.panelInside else { return }
            // A one-shot position check bridges the small gap without global mouse polling.
            if let panel = self.panel, panel.frame.contains(NSEvent.mouseLocation) { return }
            self.panel?.orderOut(nil)
            self.openedByClick = false
        }
    }

    private func showSettings() {
        panel?.orderOut(nil)
        openedByClick = false
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 620),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.title = "AI Usage Monitor · Configurações"
            window.contentView = NSHostingView(rootView: SettingsView(coordinator: environment.coordinator))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        Task {
            await environment.coordinator.shutdown()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        closeTask?.cancel()
        environment.coordinator.stop()
    }
}
