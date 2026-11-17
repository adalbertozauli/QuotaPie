import Foundation
import UserNotifications

actor HistoryStore {
    private let file: URL
    init(file: URL = ClaudeLocalSource.directory.appendingPathComponent("history.json")) { self.file = file }
    func read(retentionDays: Int) -> [UsageHistoryEntry] {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size < 20_000_000,
              let data = try? Data(contentsOf: file),
              let entries = try? JSONDecoder().decode([UsageHistoryEntry].self, from: data) else { return [] }
        return retained(entries, days: retentionDays)
    }
    func save(_ entries: [UsageHistoryEntry], retentionDays: Int) throws -> [UsageHistoryEntry] {
        let entries = retained(entries, days: retentionDays)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(entries).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        return entries
    }
    private func retained(_ entries: [UsageHistoryEntry], days: Int) -> [UsageHistoryEntry] {
        let cutoff = Date.now.addingTimeInterval(-Double(max(1, min(90, days))) * 86400)
        return Array(entries.filter { $0.timestamp >= cutoff }.suffix(100_000))
    }
    func clear() throws {
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}

struct AlertPolicy {
    static func crossed(previous: Double?, current: Double?) -> Int? {
        guard let previous = UsageWindow.validPercent(previous), let current = UsageWindow.validPercent(current) else { return nil }
        return [5, 10, 25].first { current <= Double($0) && previous > Double($0) }
    }
    static func renewed(previous: UsageWindow, current: UsageWindow, now: Date) -> Bool {
        guard let oldReset = previous.resetAt, oldReset <= now,
              let newReset = current.resetAt, newReset > now, newReset > oldReset,
              let old = previous.usedPercent, let new = current.usedPercent else { return false }
        return new < old
    }
}

actor UsageNotifications {
    private var sent: Set<String> = []
    func evaluate(_ snapshot: UsageSnapshot, previous: UsageSnapshot?, enabled: Bool, renewal: Bool) async {
        guard enabled || renewal, snapshot.source != .demonstration,
              snapshot.state == .connected || snapshot.state == .partial,
              !snapshot.isStale(at: .now, interval: 120), let previous,
              previous.source == snapshot.source else { return }
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized else { return }
        for window in snapshot.windows {
            guard let old = previous.windows.first(where: { $0.id == window.id }) else { continue }
            let threshold = enabled ? AlertPolicy.crossed(previous: old.availablePercent, current: window.availablePercent) : nil
            let renewed = renewal && AlertPolicy.renewed(previous: old, current: window, now: .now)
            guard threshold != nil || renewed else { continue }
            let key = "\(snapshot.provider.id).\(window.id).\(window.resetAt?.timeIntervalSince1970 ?? 0).\(threshold ?? -1)"
            guard sent.insert(key).inserted else { continue }
            if sent.count > 1000 { sent = [key] }
            let content = UNMutableNotificationContent()
            content.title = renewed ? "\(snapshot.provider.name): renovação confirmada" : "\(snapshot.provider.name): cota reduzida"
            content.body = renewed ? "A fonte confirmou uma nova janela para \(window.name)." : "\(window.name): \(window.availablePercent?.formatted() ?? "—")% disponível."
            do { try await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil)) }
            catch { sent.remove(key) }
        }
    }
}
