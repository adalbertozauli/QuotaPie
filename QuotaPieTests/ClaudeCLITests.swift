import Foundation
import Testing
@testable import QuotaPie

struct ClaudeCLITests {
    static let now = ISO8601DateFormatter().date(from: "2026-11-15T18:50:00Z") ?? .distantPast
    static let panel = """
    Session
    Usage: 0 input, 0 output
    Current session
    ██████████ 98% used
    Resets 4:20pm (America/Sao_Paulo)
    Current week (all models)
    ███ 39% used
    Resets Nov 18 at 12pm (America/Sao_Paulo)
    Current week (Fable)
    0% used
    Resets Nov 18 at 12pm (America/Sao_Paulo)
    What's contributing to your limits usage?
    98% Start fresh when you switch tasks
    94% Stop sessions you no longer need
    MCP servers
    31% of usage
    """

    @Test func screenshotWindowsStaySeparate() throws {
        let snapshot = try ClaudeUsageParser.parse(Self.panel, now: Self.now)
        #expect(snapshot.windows.map(\.availablePercent) == [2, 61, 100])
        #expect(snapshot.windows.map(\.id) == ["five_hour", "seven_day", "seven_day_fable"])
        #expect(snapshot.source == .localClaudeCLI)
        #expect(snapshot.state == .connected)
        let iso = ISO8601DateFormatter()
        #expect(snapshot.windows[0].resetAt == iso.date(from: "2026-11-15T19:20:00Z"))
        #expect(snapshot.windows[1].resetAt == iso.date(from: "2026-11-18T15:00:00Z"))
    }

    @Test func unknownAndInvalidStayUnknown() throws {
        let missing = Self.panel.replacingOccurrences(of: "98% used", with: "unavailable")
            .replacingOccurrences(of: "39% used", with: "101% used")
            .replacingOccurrences(of: "Resets Nov 18 at 12pm (America/Sao_Paulo)", with: "Resets soon")
        let snapshot = try ClaudeUsageParser.parse(missing, now: Self.now)
        #expect(snapshot.windows[0].usedPercent == nil)
        #expect(snapshot.windows[1].usedPercent == nil)
        #expect(snapshot.windows[2].availablePercent == 100)
        #expect(snapshot.windows[2].resetAt == nil)
        #expect(snapshot.state == .partial)
    }

    @Test(arguments: [
        "", "What's contributing to your limits usage?\n98% used",
        "Session\n98% used", "Current session\n-5% used",
        "Current session\nNaN% used", "Current session\n1e2% used",
        "Current session\n37% used\nRefreshing…",
        "Current week (Fable)   0 input, 0 output\n2% used",
        "Current session\n10% used\nCurrent session\n20% used"
    ])
    func rejectNonQuotaAndUnfinishedScreens(_ text: String) {
        #expect(throws: UsageFetchError.self) { try ClaudeUsageParser.parse(text, now: Self.now) }
    }

    @Test func leftPercentAndDecimal() throws {
        let result = try ClaudeUsageParser.parse("Current session\n62.5% left", now: Self.now)
        #expect(result.windows.first?.usedPercent == 37.5)
        #expect(result.windows.first?.resetAt == nil)
    }

    @Test func redrawUsesNewCellsAndEraseRemovesOldQuota() throws {
        var screen = ClaudeTerminalScreen()
        screen.replay(Data("Current session\r\n98% used\u{1b}[2;1H37% used\u{1b}[K".utf8))
        #expect(screen.supported)
        #expect(try ClaudeUsageParser.parse(screen.text).windows.first?.usedPercent == 37)
        var erased = ClaudeTerminalScreen()
        erased.replay(Data("Current session\r\n98% used\u{1b}[2J\u{1b}[HLoading usage".utf8))
        #expect(throws: UsageFetchError.self) { try ClaudeUsageParser.parse(erased.text) }
    }

    @Test func privateTitlesAndAnsiAreNotData() throws {
        var screen = ClaudeTerminalScreen()
        screen.replay(Data("\u{1b}]0;private account\u{7}\u{1b}[?25l\u{1b}[32mCurrent session\u{1b}[0m\r\n0% used".utf8))
        #expect(screen.supported)
        #expect(!screen.text.contains("private account"))
        #expect(try ClaudeUsageParser.parse(screen.text).windows.first?.availablePercent == 100)
        var unsupported = ClaudeTerminalScreen()
        unsupported.replay(Data("\u{1b}[1L".utf8))
        #expect(!unsupported.supported)
    }

    @Test func scrollRegionInitializationAndRedraw() throws {
        var screen = ClaudeTerminalScreen()
        screen.replay(Data("\u{1b}[rCurrent session\r\n98% used".utf8))
        #expect(screen.supported)
        #expect(try ClaudeUsageParser.parse(screen.text).windows.first?.usedPercent == 98)
        var region = ClaudeTerminalScreen()
        region.replay(Data("HEADER\u{1b}[2;3r\u{1b}[2;1HA\r\nB\r\nC".utf8))
        let rows = region.text.components(separatedBy: "\n")
        #expect(region.supported)
        #expect(rows[0] == "HEADER")
        #expect(rows[1] == "B")
        #expect(rows[2] == "C")
        var invalid = ClaudeTerminalScreen()
        invalid.replay(Data("\u{1b}[4;2r".utf8))
        #expect(!invalid.supported)
    }

    @Test func timezoneAndRollover() {
        let iso = ISO8601DateFormatter()
        let now = iso.date(from: "2026-12-31T23:00:00Z") ?? .distantPast
        #expect(ClaudeUsageParser.resetDate("Resets Jan 2 at 12pm (UTC)", now: now, weekly: true)
                == iso.date(from: "2027-01-02T12:00:00Z"))
        #expect(ClaudeUsageParser.resetDate("Resets 1am (UTC)", now: now, weekly: false)
                == iso.date(from: "2027-01-01T01:00:00Z"))
        #expect(ClaudeUsageParser.resetDate("Resets 1am", now: now, weekly: false) == nil)
        #expect(ClaudeUsageParser.resetDate("Resets Feb 30 at 12pm (UTC)", now: now, weekly: true) == nil)
        #expect(ClaudeUsageParser.resetDate("Resets 10pm (UTC)", now: now, weekly: false) == nil)
    }

    @Test func providerUsesOnlyCapturedData() async throws {
        let provider = ClaudeCLIProvider(transport: StubTransport(text: "Current session\n100% used"))
        let snapshot = try await provider.fetchUsage()
        #expect(snapshot.windows.first?.availablePercent == 0)
        #expect(snapshot.source == .localClaudeCLI)
    }

    @Test func providerPropagatesTimeoutAndCancellation() async {
        do {
            _ = try await ClaudeCLIProvider(transport: FailingTransport()).fetchUsage()
            Issue.record("Timeout must propagate")
        } catch { #expect(error as? UsageFetchError == .timeout) }
        let task = Task { try await ClaudeCLIProvider(transport: WaitingTransport()).fetchUsage() }
        task.cancel()
        do { _ = try await task.value; Issue.record("Cancellation must propagate") }
        catch { #expect(error is CancellationError) }
    }

    private struct StubTransport: ClaudeUsageTransport {
        let text: String
        func capture() async throws -> String { text }
    }
    private struct FailingTransport: ClaudeUsageTransport {
        func capture() async throws -> String { throw UsageFetchError.timeout }
    }
    private struct WaitingTransport: ClaudeUsageTransport {
        func capture() async throws -> String {
            try await Task.sleep(for: .seconds(60))
            return ""
        }
    }
}
