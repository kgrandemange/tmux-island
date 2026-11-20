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

