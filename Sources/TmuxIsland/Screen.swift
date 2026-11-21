import Foundation

/// An agent's screen: heuristics on the pane's content (complementing the hooks).
enum Screen {
    static func isWorking(_ lines: [String]) -> Bool {
        lines.suffix(12).contains { $0.localizedCaseInsensitiveContains("esc to interrupt") || $0.localizedCaseInsensitiveContains("ctrl+c to interrupt") }
    }

    static func isWaiting(_ lines: [String]) -> Bool {
        lines.suffix(14).contains {
            $0.contains("Do you want to") || $0.contains("❯ 1. Yes") || $0.contains("(y/n)") || $0.contains("[Y/n]")
                || $0.localizedCaseInsensitiveContains("Esc to cancel")
        }
    }

    /// Permission menu currently displayed at the bottom of the screen: lines "1. Yes", "2. …", "3. No…".
    /// Ignores numbered lists of the conversation (the menu must end within the last lines).
    static func pendingOptions(_ lines: [String]) -> [PermissionOption] {
        let box = CharacterSet(charactersIn: " │┃╎")
        let pattern = try! NSRegularExpression(pattern: #"^([❯>›])?\s*(\d{1,2})[.)]\s+(\S.*)$"#)
        var block: [PermissionOption] = []
        var blockEnd = -1
        var best: (options: [PermissionOption], end: Int)?
        for (i, raw) in lines.enumerated() {
            let t = raw.trimmingCharacters(in: box)
            let range = NSRange(t.startIndex..., in: t)
            guard let m = pattern.firstMatch(in: t, range: range),
                  let numRange = Range(m.range(at: 2), in: t), let n = Int(t[numRange]),
                  let labelRange = Range(m.range(at: 3), in: t) else { continue }
            let selected = m.range(at: 1).location != NSNotFound
            let label = t[labelRange].trimmingCharacters(in: box)
            if n == 1 { block = []; blockEnd = i }
            guard n == block.count + 1 else { continue }
            block.append(PermissionOption(number: n, label: label, selected: selected))
            blockEnd = i
            if block.count >= 2 { best = (block, blockEnd) }
        }
        guard let best, best.end >= lines.count - 6 else { return [] }
        return best.options
    }

    /// Shells / sub-agents still active in the background, read from Claude Code's footer
    /// ("3 background tasks") or the end-of-turn line ("2 shells still running").
    static func backgroundSummary(_ lines: [String]) -> String? {
        let recent = lines.suffix(10)
        for line in recent.reversed() {
            if let n = number(in: line, before: "background tasks?") { return L10n.plural("background.task", n) }
        }
        for line in recent.reversed() {
            if let n = number(in: line, before: "shells? still running") { return L10n.plural("background.shell", n) }
        }
        return nil
    }

    private static func number(in text: String, before pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"(\d+)\s+"# + pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    /// Claude prints "Interrupted" after an Esc: that is not a finished task worth reporting.
    static func isInterrupted(_ lines: [String]) -> Bool {
        lines.suffix(12).contains { $0.contains("Interrupted") }
    }

    /// Last raw lines of the pane (without decorative rules), for the hover preview.
    static func preview(_ lines: [String]) -> [String] {
        let noise = CharacterSet(charactersIn: "─━│┃╭╮╰╯┌┐└┘ ╌")
        return lines.filter { l in !l.unicodeScalars.allSatisfy { noise.contains($0) } }
            .suffix(10).map { String($0.prefix(130)) }
    }

    static func meaningful(_ lines: [String]) -> [String] {
        let noise = CharacterSet(charactersIn: "─━│┃╭╮╰╯┌┐└┘ >❯|╌")
        return lines.filter { line in
            if line.unicodeScalars.allSatisfy({ noise.contains($0) }) { return false }
            let l = line.lowercased()
            return !(l.contains("? for shortcuts") || l.contains("bypass permissions") || l.contains("esc to interrupt")
                || l.contains("accept edits") || l.hasPrefix("> ") || l.hasPrefix("❯") || l.hasPrefix("│ >") || l.hasPrefix("│"))
        }
        .suffix(2).map { String($0.prefix(140)) }
    }
}

