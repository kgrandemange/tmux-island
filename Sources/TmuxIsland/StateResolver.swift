import Foundation

/// Mémoire d'un agent entre deux relevés.
struct Track: Equatable {
    var state: AgentState = .idle
    var since: Date = Date()
    var ackedHookTS: Double = 0
    var doneAcked = false
}

/// Tout ce qu'on sait d'un agent à un instant donné.
struct Signals {
    var hook: HookEvent?
    /// Champ `status` du fichier de session Claude Code (`busy` / `idle`) : source la plus fiable.
    var sessionStatus: String?
    var sessionStatusAt: Date?
    var screenWorking = false
    var screenWaiting = false
    var screenInterrupted = false
    var userHere = false
    var now = Date()
}

/// Machine à états d'un agent (fonction pure, testée dans `Tests/`).
enum StateResolver {
    static func resolve(old: Track, signals s: Signals) -> Track {
        var tr = old
        var new: AgentState

        if let status = s.sessionStatus?.lowercased() {
            // Un hook « waiting » plus récent que le dernier changement de statut = demande de validation en cours.
            let hookWaiting = s.hook?.state == "waiting"
                && (s.sessionStatusAt.map { s.hook!.ts > $0.timeIntervalSince1970 } ?? true)
            let statusWaiting = status.contains("wait") || status.contains("permission") || status.contains("input")
            if s.screenWaiting || hookWaiting || statusWaiting {
                new = .waiting
            } else if ["busy", "running", "working"].contains(status) {
                new = .working
            } else if s.screenInterrupted {
                // L'utilisateur a interrompu l'agent (Esc) : rien à signaler.
                new = .idle
                tr.doneAcked = true
            } else if old.state == .working || old.state == .waiting {
                new = .done
                tr.doneAcked = false
            } else if old.state == .done && !tr.doneAcked {
                new = .done
            } else {
                new = .idle
            }
        } else if let h = s.hook {
            let age = s.now.timeIntervalSince1970 - h.ts
            switch h.state {
            case "waiting": new = .waiting
            case "working":
                // Un Esc (interruption) ne déclenche pas de hook Stop : on recoupe avec l'écran.
                new = s.screenWaiting ? .waiting : ((s.screenWorking || age < 6) ? .working : .idle)
            case "done":
                new = (tr.ackedHookTS == h.ts) ? .idle : (s.screenWorking ? .working : .done)
            default: new = .idle
            }
        } else {
            if s.screenWaiting { new = .waiting }
            else if s.screenWorking { new = .working }
            else if old.state == .working { new = .done; tr.doneAcked = false }
            else if old.state == .done && !tr.doneAcked { new = .done }
            else { new = .idle }
        }

        // L'utilisateur regarde déjà ce pane : on acquitte automatiquement le « terminé ».
        if s.userHere && new == .done {
            new = .idle
            tr.doneAcked = true
            if let h = s.hook { tr.ackedHookTS = h.ts }
        }

        if new != old.state {
            tr.state = new
            if new == .done || new == .waiting {
                tr.since = s.sessionStatusAt ?? s.hook.map { Date(timeIntervalSince1970: $0.ts) } ?? s.now
            } else {
                tr.since = s.now
            }
        }
        return tr
    }
}
