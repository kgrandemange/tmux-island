import Foundation

/// An agent's memory between two refreshes.
struct Track: Equatable {
    var state: AgentState = .idle
    var since: Date = Date()
    var ackedHookTS: Double = 0
    var doneAcked = false
}

/// Everything known about an agent at a given moment.
struct Signals {
    var hook: HookEvent?
    /// `status` field of the Claude Code session file (`busy` / `idle` / `shell`): the most reliable source.
    var sessionStatus: String?
    var sessionStatusAt: Date?
    var screenWorking = false
    var screenWaiting = false
    var screenInterrupted = false
    var userHere = false
    var now = Date()
}

/// An agent's state machine (a pure function, tested in `Tests/`).
enum StateResolver {
    static func resolve(old: Track, signals s: Signals) -> Track {
        var tr = old
        var new: AgentState

        if let status = s.sessionStatus?.lowercased() {
            // A "waiting" hook newer than the last status change = a permission request in progress.
            let hookWaiting = s.hook?.state == "waiting"
                && (s.sessionStatusAt.map { s.hook!.ts > $0.timeIntervalSince1970 } ?? true)
            let statusWaiting = status.contains("wait") || status.contains("permission") || status.contains("input")
            if s.screenWaiting || hookWaiting || statusWaiting {
                new = .waiting
            } else if ["busy", "running", "working"].contains(status) {
                new = .working
            } else if status == "shell" || status.contains("background") {
                // Turn over, but shells / sub-agents are still running: neither "running" nor "done"
                // (no alert). The alert comes if the agent wakes up, works, then finishes.
                new = .background
            } else if s.screenInterrupted {
                // The user interrupted the agent (Esc): nothing to report.
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
                // An Esc (interruption) does not fire a Stop hook: cross-check with the screen.
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

        // The user is already looking at this pane: automatically acknowledge the "done".
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
