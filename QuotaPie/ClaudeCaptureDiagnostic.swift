import Foundation

/// A single local diagnostic record. Only fixed stage names, counters and booleans;
/// never terminal contents, prompts, credentials, paths or account identifiers.
struct ClaudeCaptureDiagnostic: Codable {
    var date = Date.now
    var stage = "starting"
    var bytes = 0
    var unsupportedControl: String?
    var exitStatus: Int32?
    var hasSession = false
    var hasWeek = false
    var hasTrustPrompt = false
    var hasLoginPrompt = false
    var hasReadyPrompt = false
    var hasArgumentError = false
    var hasUsageLoadingError = false

    mutating func inspect(_ text: String) {
        hasSession = text.contains("Current session")
        hasWeek = text.contains("Current week")
        hasTrustPrompt = text.contains("Yes, I trust this folder")
        hasLoginPrompt = text.contains("Select login method") || text.contains("Not logged in")
        hasReadyPrompt = text.contains("❯")
        hasArgumentError = text.contains("unknown option") || text.contains("error: option")
        hasUsageLoadingError = text.contains("Failed to load usage")
    }

    func save() {
        let url = ClaudeLocalSource.directory.appendingPathComponent("claude-diagnostic.json")
        guard let data = try? JSONEncoder().encode(self) else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { /* Diagnostic failure must never affect quota refresh. */ }
    }
}
