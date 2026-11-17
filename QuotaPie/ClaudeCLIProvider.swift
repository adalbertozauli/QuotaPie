import Foundation
import Darwin

protocol ClaudeUsageTransport: Sendable {
    func capture() async throws -> String
}

struct ClaudeCLIProvider: UsageProvider {
    let id = "claude"
    let displayName = "Claude"
    let transport: any ClaudeUsageTransport

    init(transport: any ClaudeUsageTransport = ClaudePTYTransport()) { self.transport = transport }

    func checkAvailability() async -> ProviderAvailability {
        ProviderAvailability(available: ClaudePTYTransport.executable != nil,
                             message: "Requer Claude Code instalado e autenticado; leitura experimental de /usage.")
    }

    func fetchUsage() async throws -> UsageSnapshot {
        try ClaudeUsageParser.parse(await transport.capture())
    }
}

/// Owns a short-lived CLI, not the user's interactive session.
/// No stdout, account identifiers or credentials are logged or persisted.
actor ClaudePTYTransport: ClaudeUsageTransport {
    static var executable: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["\(home)/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
            .first(where: { FileManager.default.isExecutableFile(atPath: $0) })
            .map { URL(fileURLWithPath: $0) }
    }

    private var running = false

    func capture() async throws -> String {
        guard !running else { throw UsageFetchError.processFailed }
        running = true
        var diagnostic = ClaudeCaptureDiagnostic()
        defer { diagnostic.save() }
        defer { running = false }
        guard let binary = Self.executable else { throw UsageFetchError.claudeNotInstalled }
        try Task.checkCancellation()
        let directory = try Self.probeDirectory()
        var master: Int32 = -1
        var slave: Int32 = -1
        var size = winsize(ws_row: 200, ws_col: 160, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else {
            diagnostic.stage = "pty-unavailable"
            throw UsageFetchError.terminalUnavailable
        }
        let input = FileHandle(fileDescriptor: slave, closeOnDealloc: true)
        let terminal = FileHandle(fileDescriptor: master, closeOnDealloc: true)
        let process = Process()
        defer {
            // The probe has no tools, hooks, MCP servers or generated turns.
            // Kill only our child to guarantee cancellation never leaves a CLI behind.
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            try? input.close()
            try? terminal.close()
        }
        var attributes = termios()
        if tcgetattr(slave, &attributes) == 0 {
            attributes.c_lflag &= ~tcflag_t(ECHO)
            _ = tcsetattr(slave, TCSANOW, &attributes)
        }
        guard fcntl(master, F_SETFL, O_NONBLOCK) != -1 else { throw UsageFetchError.terminalUnavailable }
        process.executableURL = binary
        process.currentDirectoryURL = directory
        process.arguments = ["--safe-mode", "--strict-mcp-config", "--tools", "",
                             "--ax-screen-reader", "--settings",
                             #"{"remoteControlAtStartup":false,"disableAllHooks":true}"#, "/usage"]
        var environment = ProcessInfo.processInfo.environment
        // Preserve authentication owned by Claude, but never pass an API key to this subscription probe.
        for key in ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "ANTHROPIC_BASE_URL",
                    "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX", "CLAUDE_CODE_USE_FOUNDRY"] {
            environment.removeValue(forKey: key)
        }
        environment["TERM"] = "xterm-256color"
        environment["COLUMNS"] = "160"
        environment["LINES"] = "200"
        environment["PWD"] = directory.path
        process.environment = environment
        process.standardInput = input
        process.standardOutput = input
        process.standardError = input
        diagnostic.stage = "launching"
        do { try process.run() } catch { diagnostic.stage = "launch-failed"; throw UsageFetchError.processFailed }
        diagnostic.stage = "capturing"
        try input.close()

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(16))
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        var lastScreen = ""
        var stableSince = clock.now
        var trustActions = 0
        var lastTrustScreen = ""
        while clock.now < deadline {
            try Task.checkCancellation()
            let count = read(master, &buffer, buffer.count)
            if count > 0 {
                bytes.append(contentsOf: buffer.prefix(count))
                guard bytes.count <= 524288 else { throw UsageFetchError.invalidResponse }
                var screen = ClaudeTerminalScreen()
                screen.replay(bytes)
                diagnostic.bytes = bytes.count
                diagnostic.unsupportedControl = screen.unsupportedControl
                let text = screen.text
                diagnostic.inspect(text)
                guard screen.supported else { diagnostic.stage = "unsupported-terminal-control"; throw UsageFetchError.invalidResponse }
                if text != lastScreen { lastScreen = text; stableSince = clock.now }
                if text.contains("Yes, I trust this folder"), text != lastTrustScreen, trustActions < 4 {
                    // Trust only our verified, empty, private probe directory, never the user's project.
                    // Confirm only when the selection marker is actually on the trust option.
                    let selected = text.components(separatedBy: .newlines).first {
                        $0.contains("❯") && ($0.contains("Yes, I trust") || $0.contains("No, exit"))
                    }
                    if let selected {
                        let keys = selected.contains("Yes, I trust") ? "\r" : "\u{1b}[A"
                        try terminal.write(contentsOf: Data(keys.utf8))
                        trustActions += 1
                        lastTrustScreen = text
                    }
                }
                if text.contains("Select login method") || text.contains("Please run /login") ||
                    text.contains("Not logged in") { throw UsageFetchError.unauthenticated }
                if text.localizedCaseInsensitiveContains("rate limit") && text.contains("429") {
                    throw UsageFetchError.http(429, retryAfter: 120)
                }
            } else if count < 0 && errno != EAGAIN && errno != EWOULDBLOCK && errno != EIO {
                throw UsageFetchError.processFailed
            }
            // Wait for the final quota screen, including delayed model rows, to settle.
            if clock.now - stableSince >= .seconds(2),
               (try? ClaudeUsageParser.parse(lastScreen)) != nil {
                diagnostic.stage = "success"
                return lastScreen
            }
            if !process.isRunning {
                diagnostic.stage = "process-exited"
                diagnostic.exitStatus = process.terminationStatus
                throw UsageFetchError.invalidResponse
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        diagnostic.stage = "timeout"
        throw UsageFetchError.timeout
    }

    private static func probeDirectory() throws -> URL {
        let directory = ClaudeLocalSource.directory.appendingPathComponent("ClaudeProbe", isDirectory: true)
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Never auto-trust a symlink or a directory containing project/user instructions.
        guard directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL,
              try manager.contentsOfDirectory(atPath: directory.path).isEmpty else {
            throw UsageFetchError.claudeProbeDirectory
        }
        let info = try manager.attributesOfItem(atPath: directory.path)
        guard (info[.ownerAccountID] as? NSNumber)?.uint32Value == getuid() else {
            throw UsageFetchError.claudeProbeDirectory
        }
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        return directory
    }
}
