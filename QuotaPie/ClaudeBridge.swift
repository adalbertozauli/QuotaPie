import Foundation
import Darwin
import CoreFoundation

enum ClaudeBridge {
    /// This mode accepts Claude's documented stdin payload, but persists only quota fields.
    static func capture() -> Int32 {
        do {
            let data = try FileHandle.standardInput.read(upToCount: 1_048_577) ?? Data()
            let output = try sanitizedData(data)
            try FileManager.default.createDirectory(at: ClaudeLocalSource.directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            try output.write(to: ClaudeLocalSource.file, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ClaudeLocalSource.file.path)
            let snapshot = try ClaudeLocalSource.parse(output)
            print(snapshot.windows.isEmpty
                  ? "AI Usage Monitor · aguardando cotas do Claude Code"
                  : "AI Usage Monitor · métricas atualizadas")
            return 0
        } catch { return 1 }
    }

    static func sanitizedData(_ data: Data, now: Date = .now) throws -> Data {
            guard data.count <= 1_048_576,
                  let input = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw UsageFetchError.invalidResponse }
            let limits = input["rate_limits"] as? [String: Any] ?? [:]
            var sanitized: [String: Any] = [:]
            for key in ["five_hour", "seven_day"] {
                guard let source = limits[key] as? [String: Any] else { continue }
                var window: [String: Any] = [:]
                if let number = source["used_percentage"] as? NSNumber,
                   CFGetTypeID(number) != CFBooleanGetTypeID(),
                   let value = UsageWindow.validPercent(number.doubleValue) { window["used_percentage"] = value }
                if let number = source["resets_at"] as? NSNumber,
                   CFGetTypeID(number) != CFBooleanGetTypeID(),
                   let date = UsageWindow.date(seconds: number.doubleValue) { window["resets_at"] = date.timeIntervalSince1970 }
                sanitized[key] = window
            }
            let output: [String: Any] = ["capturedAt": now.timeIntervalSince1970, "rate_limits": sanitized]
            return try JSONSerialization.data(withJSONObject: output)
    }
}
