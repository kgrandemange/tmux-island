import AppKit
import Combine
import Foundation

private struct Snapshot {
    var panes: [Pane] = []
    var kinds: [String: String] = [:]
    var hooks: [String: HookEvent] = [:]
    var tails: [String: [String]] = [:]
    var clients: [TmuxClient] = []
    var terminalPIDs: Set<Int32> = []
}

private struct Track {
    var state: AgentState = .idle
    var since: Date = Date()
    var ackedHookTS: Double = 0
    var doneAcked = false
}

/// Écran d'un agent : heuristiques sur le contenu du pane (en complément des hooks).
private enum Screen {
    static func isWorking(_ lines: [String]) -> Bool {
        lines.suffix(12).contains { $0.localizedCaseInsensitiveContains("esc to interrupt") || $0.localizedCaseInsensitiveContains("ctrl+c to interrupt") }
    }

    static func isWaiting(_ lines: [String]) -> Bool {
        lines.suffix(14).contains {
            $0.contains("Do you want to") || $0.contains("❯ 1. Yes") || $0.contains("(y/n)") || $0.contains("[Y/n]")
                || $0.localizedCaseInsensitiveContains("Esc to cancel")
        }
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

@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var sessions: [TmuxSession] = []
    @Published private(set) var tmuxRunning = true

    /// Émis quand un agent passe en « terminé » ou « attend une réponse ».
    let alerts = PassthroughSubject<Agent, Never>()

    private var tracks: [String: Track] = [:]
    private var firstPoll = true
    private var busy = false
    private var timer: Timer?

    /// Agents affichés en lignes dans l'île : tout sauf les inactifs (ceux-ci restent accessibles via les sessions).
    var visibleAgents: [Agent] { agents.filter { $0.state != .idle } }
    var idleCount: Int { agents.count - visibleAgents.count }
    var attentionAgents: [Agent] { agents.filter { $0.state.needsAttention } }
    var workingCount: Int { agents.filter { $0.state == .working }.count }
    var waitingCount: Int { agents.filter { $0.state == .waiting }.count }
    var doneCount: Int { agents.filter { $0.state == .done }.count }

    func start() {
        poll()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    /// Prochain agent à traiter : en attente d'abord, puis terminés, du plus ancien au plus récent.
    func nextAttention() -> Agent? {
        attentionAgents.sorted { ($0.state.priority, $0.since) < ($1.state.priority, $1.since) }.first
    }

    func acknowledge(_ paneID: String) {
        guard var tr = tracks[paneID] else { return }
        tr.doneAcked = true
        if let hook = lastHooks[paneID] { tr.ackedHookTS = hook.ts }
        if tr.state == .done { tr.state = .idle; tr.since = Date() }
        tracks[paneID] = tr
        if let i = agents.firstIndex(where: { $0.id == paneID }), agents[i].state == .done {
            agents[i].state = .idle
        }
    }

    private var lastHooks: [String: HookEvent] = [:]

    private func poll() {
        guard !busy else { return }
        busy = true
        Task { @MainActor [weak self] in
            let snap = await Task.detached(priority: .utility) { Self.collect() }.value
            self?.apply(snap)
            self?.busy = false
        }
    }

    private nonisolated static func collect() -> Snapshot {
        var snap = Snapshot()
        snap.panes = TmuxService.listPanes()
        guard !snap.panes.isEmpty else { return snap }
        let ps = ProcessTable()
        snap.hooks = HookStore.readAll(validPanes: Set(snap.panes.map(\.id)))
        for pane in snap.panes {
            if let k = ps.agentKind(under: pane.pid) { snap.kinds[pane.id] = k }
        }
        for pane in snap.panes where snap.kinds[pane.id] != nil || snap.hooks[pane.id] != nil {
            snap.tails[pane.id] = TmuxService.capture(pane.id)
        }
        snap.clients = TmuxService.listClients()
        for c in snap.clients {
            for a in [c.pid] + ps.ancestors(of: c.pid) {
                if NSRunningApplication(processIdentifier: a)?.activationPolicy == .regular { snap.terminalPIDs.insert(a) }
            }
        }
        return snap
    }

    private func apply(_ snap: Snapshot) {
        tmuxRunning = !snap.panes.isEmpty
        lastHooks = snap.hooks
        let now = Date()
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let userIsInTerminal = frontPID.map { snap.terminalPIDs.contains($0) } ?? false
        let clientSessions = Set(snap.clients.map(\.session))

        var result: [Agent] = []
        for pane in snap.panes {
            let hook = snap.hooks[pane.id]
            guard let kind = snap.kinds[pane.id] ?? hook?.agent else { continue }
            let tail = snap.tails[pane.id] ?? []
            let working = Screen.isWorking(tail)
            let waiting = Screen.isWaiting(tail)
            var tr = tracks[pane.id] ?? Track(state: .idle, since: now)
            let old = tr.state

            var new: AgentState
            if let h = hook {
                let age = now.timeIntervalSince1970 - h.ts
                switch h.state {
                case "waiting": new = .waiting
                case "working":
                    // Un Esc (interruption) ne déclenche pas de hook Stop : on recoupe avec l'écran.
                    new = waiting ? .waiting : ((working || age < 6) ? .working : .idle)
                case "done":
                    new = (tr.ackedHookTS == h.ts) ? .idle : (working ? .working : .done)
                default: new = .idle
                }
            } else {
                if waiting { new = .waiting }
                else if working { new = .working }
                else if old == .working { new = .done; tr.doneAcked = false }
                else if old == .done && !tr.doneAcked { new = .done }
                else { new = .idle }
            }

            // L'utilisateur regarde déjà ce pane : on acquitte automatiquement le « terminé ».
            let userHere = userIsInTerminal && pane.isFocusedInSession && clientSessions.contains(pane.session)
            if userHere && new == .done {
                new = .idle
                tr.doneAcked = true
                if let h = hook { tr.ackedHookTS = h.ts }
            }

            if new != old {
                tr.state = new
                tr.since = (new == .done || new == .waiting) ? (hook.map { Date(timeIntervalSince1970: $0.ts) } ?? now) : now
            }
            tracks[pane.id] = tr

            let agent = Agent(pane: pane, kind: kind, state: new, since: tr.since,
                              message: hook?.message, tail: Screen.meaningful(tail))
            result.append(agent)

            if new != old, new.needsAttention, !firstPoll, !userHere { alerts.send(agent) }
        }
        tracks = tracks.filter { id, _ in result.contains(where: { $0.id == id }) }
        result.sort { ($0.state.priority, $0.since) < ($1.state.priority, $1.since) }
        if result != agents { agents = result }

        // Sessions / fenêtres
        var sess: [String: TmuxSession] = [:]
        for pane in snap.panes {
            var s = sess[pane.session] ?? TmuxSession(name: pane.session, attached: pane.sessionAttached, windows: [])
            if let wi = s.windows.firstIndex(where: { $0.index == pane.windowIndex }) {
                s.windows[wi].panes.append(pane)
            } else {
                s.windows.append(TmuxWindow(index: pane.windowIndex, name: pane.windowName, active: pane.windowActive, panes: [pane]))
            }
            sess[pane.session] = s
        }
        sessions = sess.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { var s = $0; s.windows.sort { $0.index < $1.index }; return s }
        firstPoll = false
    }

    func state(ofWindow w: TmuxWindow) -> AgentState? {
        agents.filter { a in w.panes.contains(where: { $0.id == a.id }) }.map(\.state).min(by: { $0.priority < $1.priority })
    }
}
