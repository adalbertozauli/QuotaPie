import Foundation

/// Parses only the current terminal screen, never the accumulated history of redraws.
enum ClaudeUsageParser {
    static func parse(_ screen: String, now: Date = .now) throws -> UsageSnapshot {
        guard !screen.localizedCaseInsensitiveContains("refreshing"),
              !screen.localizedCaseInsensitiveContains("loading usage") else {
            throw UsageFetchError.invalidResponse
        }
        let quotaArea = screen.components(separatedBy: "What's contributing").first ?? screen
        let lines = quotaArea.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        var windows: [UsageWindow] = []
        var index = 0
        while index < lines.count {
            let header = lines[index]
            let session = header == "Current session"
            let weekly = header == "Current week" || header.range(of: #"^Current week \([^()]+\)$"#, options: .regularExpression) != nil
            guard session || weekly else { index += 1; continue }
            var end = index + 1
            while end < lines.count && !lines[end].hasPrefix("Current ") &&
                    !lines[end].hasPrefix("Usage credits") { end += 1 }
            let block = lines[(index + 1)..<end]
            // Only a whole quota row with an explicit used/left suffix qualifies.
            let percentages = block.compactMap { line -> Double? in
                guard let match = line.range(of: #"(?:^|\s)\d+(?:\.\d+)?%\s+(?:used|left)\s*$"#, options: .regularExpression),
                      let number = Double(line[match].split(separator: "%")[0].trimmingCharacters(in: .whitespaces)),
                      let valid = UsageWindow.validPercent(number) else { return nil }
                return line[match].contains("left") ? 100 - valid : valid
            }
            let resetLine = block.first { $0.hasPrefix("Resets ") }
            let scope = weekly ? header.replacingOccurrences(of: "Current week", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ()")) : ""
            let id = session ? "five_hour" : (scope.isEmpty || scope == "all models" ? "seven_day" : "seven_day_\(scope.lowercased())")
            // Conflicting or duplicate quota sections are incompatible, not merged.
            guard !windows.contains(where: { $0.id == id }), percentages.count <= 1 else {
                throw UsageFetchError.invalidResponse
            }
            windows.append(UsageWindow(id: id,
                name: session ? "Sessão · 5 horas" : (scope.isEmpty || scope == "all models" ? "Semana · todos os modelos" : "Semana · \(scope)"),
                usedPercent: percentages.first,
                resetAt: resetLine.flatMap { resetDate($0, now: now, weekly: weekly) },
                durationMinutes: session ? 300 : 10080))
            index = end
        }
        guard windows.contains(where: { $0.usedPercent != nil }) else { throw UsageFetchError.invalidResponse }
        return UsageSnapshot(provider: .claude, windows: windows, fetchedAt: now, source: .localClaudeCLI,
                             state: windows.contains { $0.usedPercent == nil || $0.resetAt == nil } ? .partial : .connected,
                             message: "Consulta local /usage · leitura experimental da interface do Claude Code.")
    }

    /// Require the provider's explicit timezone. Ambiguous/unsupported dates stay unknown.
    static func resetDate(_ line: String, now: Date, weekly: Bool) -> Date? {
        guard let opening = line.lastIndex(of: "("), line.hasSuffix(")"),
              let zone = TimeZone(identifier: String(line[line.index(after: opening)..<line.index(before: line.endIndex)])) else { return nil }
        let text = line.dropFirst("Resets ".count)[..<opening]
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " at ", with: " ")
            .replacingOccurrences(of: ",", with: "")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.isLenient = false
        let formats = weekly ? ["MMM d h:mma", "MMM d ha", "MMM d HH:mm"] : ["h:mma", "ha", "HH:mm"]
        for format in formats {
            formatter.dateFormat = weekly ? "yyyy " + format : "yyyy-MM-dd " + format
            let year = calendar.component(.year, from: now)
            let prefixes: [String]
            if weekly { prefixes = [String(year), String(year + 1)] }
            else {
                let prefix = DateFormatter()
                prefix.locale = Locale(identifier: "en_US_POSIX")
                prefix.timeZone = zone
                prefix.dateFormat = "yyyy-MM-dd"
                prefixes = [now, calendar.date(byAdding: .day, value: 1, to: now)].compactMap { $0 }.map { prefix.string(from: $0) }
            }
            for prefix in prefixes {
                guard let date = formatter.date(from: prefix + " " + text),
                      date >= now.addingTimeInterval(-60),
                      date.timeIntervalSince(now) <= Double(weekly ? 7 * 86400 : 5 * 3600) + 60 else { continue }
                return date
            }
        }
        return nil
    }
}

/// Small bounded VT screen. Unsupported cursor operations invalidate the capture.
struct ClaudeTerminalScreen {
    private var cells = Array(repeating: Array(repeating: Character(" "), count: 160), count: 200)
    private var row = 0
    private var column = 0
    private var saved = (0, 0)
    private var scrollTop = 0
    private var scrollBottom = 199
    private(set) var supported = true
    private(set) var unsupportedControl: String?
    private mutating func reject(_ control: String) {
        supported = false
        if unsupportedControl == nil { unsupportedControl = control }
    }

    var text: String { cells.map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: "\n") }

    mutating func replay(_ data: Data) {
        let scalars = Array(String(decoding: data, as: UTF8.self).unicodeScalars)
        var index = 0
        while index < scalars.count {
            let value = scalars[index].value
            if value == 27 {
                index += 1
                guard index < scalars.count else { break }
                if scalars[index] == "[" {
                    index += 1
                    var parameter = ""
                    while index < scalars.count && !(0x40...0x7e).contains(scalars[index].value) {
                        parameter.unicodeScalars.append(scalars[index]); index += 1
                    }
                    guard index < scalars.count else { break }
                    execute(Character(String(scalars[index])), parameter)
                } else if scalars[index] == "]" {
                    // OSC titles/hyperlinks are never quota text.
                    index += 1
                    while index < scalars.count && scalars[index].value != 7 {
                        if scalars[index].value == 27 && index + 1 < scalars.count && scalars[index + 1] == "\\" {
                            index += 1; break
                        }
                        index += 1
                    }
                } else if scalars[index] == "7" { saved = (row, column) }
                else if scalars[index] == "8" { (row, column) = saved }
                else if scalars[index] != "=" && scalars[index] != ">" { reject("ESC-\(scalars[index].value)") }
            } else if value == 13 { column = 0 }
            else if value == 10 { advanceRow() }
            else if value == 8 { column = max(0, column - 1) }
            else if value == 9 { column = min(159, (column / 8 + 1) * 8) }
            else if value >= 32 && value != 127 {
                if column >= 160 { column = 0; advanceRow() }
                cells[row][column] = Character(String(scalars[index]))
                column += 1
            }
            index += 1
        }
    }

    private mutating func advanceRow() {
        if row == scrollBottom {
            cells.remove(at: scrollTop)
            cells.insert(Array(repeating: " ", count: 160), at: scrollBottom)
        } else { row = min(199, row + 1) }
    }

    private mutating func execute(_ command: Character, _ parameters: String) {
        let privateMode = parameters.hasPrefix("?")
        let values = parameters.replacingOccurrences(of: "?", with: "").split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let first = values.first ?? 0
        let amount = min(200, max(1, first))
        switch command {
        case "r":
            let top = max(1, first)
            let bottom = values.count > 1 && values[1] > 0 ? values[1] : 200
            guard top < bottom && bottom <= 200 else { reject("CSI-r-invalid"); return }
            scrollTop = top - 1
            scrollBottom = bottom - 1
            row = 0
            column = 0
        case "S":
            for _ in 0..<min(amount, scrollBottom - scrollTop + 1) {
                cells.remove(at: scrollTop)
                cells.insert(Array(repeating: " ", count: 160), at: scrollBottom)
            }
        case "T":
            for _ in 0..<min(amount, scrollBottom - scrollTop + 1) {
                cells.remove(at: scrollBottom)
                cells.insert(Array(repeating: " ", count: 160), at: scrollTop)
            }
        case "A": row = max(0, row - amount)
        case "B": row = min(199, row + amount)
        case "C": column = min(159, column + amount)
        case "D": column = max(0, column - amount)
        case "E": row = min(199, row + amount); column = 0
        case "F": row = max(0, row - amount); column = 0
        case "G": column = min(159, max(0, first - 1))
        case "d": row = min(199, max(0, first - 1))
        case "H", "f":
            row = min(199, max(0, first - 1))
            column = min(159, max(0, (values.count > 1 ? values[1] : 1) - 1))
        case "J":
            if first == 2 || first == 3 { cells = Array(repeating: Array(repeating: " ", count: 160), count: 200) }
            else if first == 0 {
                for r in row..<200 { for c in (r == row ? min(column, 159) : 0)..<160 { cells[r][c] = " " } }
            } else if first == 1 {
                for r in 0...row { for c in 0..<(r == row ? min(column + 1, 160) : 160) { cells[r][c] = " " } }
            } else { supported = false }
        case "K":
            let start = first == 0 ? min(column, 159) : 0
            let end = first == 1 ? min(column + 1, 160) : 160
            for c in start..<end { cells[row][c] = " " }
        case "s": saved = (row, column)
        case "u": (row, column) = saved
        case "m": break
        case "h", "l":
            if !privateMode { supported = false }
            // Alternate screen starts from an empty view; no stale values leak across it.
            if values.contains(1049) { cells = Array(repeating: Array(repeating: " ", count: 160), count: 200); row = 0; column = 0 }
        case "n", "c", "t", "q": break // Queries and cursor style do not paint text.
        default: reject("CSI-\(command)")
        }
    }
}
