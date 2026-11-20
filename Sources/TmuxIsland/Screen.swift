import Foundation

/// Écran d'un agent : heuristiques sur le contenu du pane (en complément des hooks).
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

    /// Menu de validation actuellement affiché en bas de l'écran : lignes « 1. Yes », « 2. … », « 3. No… ».
    /// Ignore les listes numérotées de la conversation (le menu doit se terminer dans les dernières lignes).
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

    /// Shells / sous-agents encore actifs en arrière-plan, lus dans le pied de page de Claude Code
    /// (« 3 background tasks ») ou la ligne de fin de tour (« 2 shells still running »).
    static func backgroundSummary(_ lines: [String]) -> String? {
        let recent = lines.suffix(10)
        for line in recent.reversed() {
            if let n = number(in: line, before: "background tasks?") { return n == 1 ? "1 tâche de fond" : "\(n) tâches de fond" }
        }
        for line in recent.reversed() {
            if let n = number(in: line, before: "shells? still running") { return n == 1 ? "1 shell" : "\(n) shells" }
        }
        return nil
    }

    private static func number(in text: String, before pattern: String) -> Int? {
        guard let re = try? NSRegularExpression(pattern: #"(\d+)\s+"# + pattern, options: .caseInsensitive),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }

    /// Claude affiche « Interrupted » après un Esc : ce n'est pas une fin de tâche à signaler.
    static func isInterrupted(_ lines: [String]) -> Bool {
        lines.suffix(12).contains { $0.contains("Interrupted") }
    }

    /// Dernières lignes brutes du pane (sans les filets décoratifs), pour l'aperçu au survol.
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

