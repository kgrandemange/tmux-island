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
    var usage: [String: ClaudeUsage.Info] = [:]
    var claude: [String: ClaudeSession] = [:]
}

@MainActor
final class AgentStore: ObservableObject {
    @Published private(set) var agents: [Agent] = []
    @Published private(set) var sessions: [TmuxSession] = []
    @Published private(set) var tmuxRunning = true
    @Published private(set) var history: [HistoryEntry] = {
        if DemoMode.active { return [] }
        guard let d = UserDefaults.standard.data(forKey: "history"),
              let h = try? JSONDecoder().decode([HistoryEntry].self, from: d) else { return [] }
        return h
    }()

    /// Émis quand un agent passe en « terminé » ou « attend une réponse ».
    let alerts = PassthroughSubject<Agent, Never>()

    private var tracks: [String: Track] = [:]
    private var firstPoll = true
    private var busy = false
    private var timer: Timer?
    private var pendingPoll = false
    private var interval: TimeInterval = 1.0
    private var watcher: FileWatcher?

    /// Cadence de relevé de secours : 1 s tant qu'un agent n'a pas de statut officiel (heuristique d'écran),
    /// sinon 3 s. Les changements de fichiers déclenchent un relevé immédiat. Surchargeable pour les tests.
    private static let debug = ProcessInfo.processInfo.environment["TMUXISLAND_DEBUG"] != nil
    private static let envInterval = ProcessInfo.processInfo.environment["TMUXISLAND_POLL_INTERVAL"].flatMap(Double.init)

    /// Agents affichés en lignes dans l'île : tout sauf les inactifs (ceux-ci restent accessibles via les sessions).
    var visibleAgents: [Agent] { agents.filter { $0.state != .idle } }
    var idleCount: Int { agents.count - visibleAgents.count }
    var attentionAgents: [Agent] { agents.filter { $0.state.needsAttention } }
    var workingCount: Int { agents.filter { $0.state == .working }.count }
    var waitingCount: Int { agents.filter { $0.state == .waiting }.count }
    var doneCount: Int { agents.filter { $0.state == .done }.count }
    var backgroundCount: Int { agents.filter { $0.state == .background }.count }

    func start() {
        poll()
        scheduleTimer(Self.envInterval ?? 1.0)
        let claudeSessions = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions").path
        watcher = FileWatcher(paths: [claudeSessions, HookStore.dir.path]) { [weak self] in
            Task { @MainActor in self?.poll() }
        }
    }

    private func scheduleTimer(_ every: TimeInterval) {
        timer?.invalidate()
        interval = every
        timer = Timer.scheduledTimer(withTimeInterval: every, repeats: true) { [weak self] _ in
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
        // Un relevé est déjà en cours : on en refera un juste après (sans en empiler plusieurs).
        guard !busy else { pendingPoll = true; return }
        busy = true
        Task { @MainActor [weak self] in
            let snap = await Task.detached(priority: .utility) { Self.collect() }.value
            self?.apply(snap)
            self?.busy = false
            if self?.pendingPoll == true { self?.pendingPoll = false; self?.poll() }
        }
    }

    private nonisolated static func collect() -> Snapshot {
        var snap = Snapshot()
        for server in TmuxService.discoverServers() {
            snap.panes += TmuxService.listPanes(server: server)
            snap.clients += TmuxService.listClients(server: server)
        }
        guard !snap.panes.isEmpty else { return snap }
        let ps = ProcessTable()
        snap.hooks = HookStore.readAll(validPanes: Set(snap.panes.map(\.id)))
        snap.claude = DemoMode.active ? [:] : ClaudeUsage.sessionsByPane(alive: { ps.cmd[$0] != nil })
        for pane in snap.panes {
            if let k = ps.agentKind(under: pane.pid) { snap.kinds[pane.id] = k }
            else if snap.claude[pane.claudeKey] != nil { snap.kinds[pane.id] = "claude" }
        }
        for pane in snap.panes where snap.kinds[pane.id] != nil || snap.hooks[pane.id] != nil {
            snap.tails[pane.id] = TmuxService.capture(pane)
        }
        for pane in snap.panes where snap.kinds[pane.id] == "claude" {
            if let c = snap.claude[pane.claudeKey], let info = ClaudeUsage.info(sessionId: c.sessionId) { snap.usage[pane.id] = info }
        }
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
            let old = tracks[pane.id] ?? Track(state: .idle, since: now)
            let userHere = userIsInTerminal && pane.isFocusedInSession && clientSessions.contains(pane.session)
            let session = snap.claude[pane.claudeKey]
            let tr = StateResolver.resolve(old: old, signals: Signals(
                hook: hook, sessionStatus: session?.status, sessionStatusAt: session?.statusUpdatedAt,
                screenWorking: working, screenWaiting: waiting, screenInterrupted: Screen.isInterrupted(tail),
                userHere: userHere, now: now))
            let new = tr.state
            tracks[pane.id] = tr

            let agent = Agent(pane: pane, kind: kind, state: new, since: tr.since,
                              message: hook?.message, tail: Screen.meaningful(tail),
                              screen: Screen.preview(tail), usage: snap.usage[pane.id],
                              options: new == .waiting ? Screen.pendingOptions(tail) : [],
                              detail: new == .background ? Screen.backgroundSummary(tail) : nil)
            result.append(agent)

            if new != old.state, new.needsAttention, !firstPoll {
                record(agent)
                if Self.debug { FileHandle.standardError.write("\(Date().timeIntervalSince1970) alert \(agent.id) \(new)\n".data(using: .utf8)!) }
                if !userHere { alerts.send(agent) }
            }
        }
        tracks = tracks.filter { id, _ in result.contains(where: { $0.id == id }) }
        // Sans agent « heuristique », les fichiers de statut suffisent : on relâche le polling de secours.
        let wanted = Self.envInterval ?? (result.contains { snap.claude[$0.id]?.status == nil } ? 1.0 : 3.0)
        if wanted != interval { scheduleTimer(wanted) }
        result.sort { ($0.state.priority, $0.since) < ($1.state.priority, $1.since) }
        if result != agents { agents = result }

        // Sessions / fenêtres
        var sess: [String: TmuxSession] = [:]
        for pane in snap.panes {
            let key = "\(pane.server ?? "")|\(pane.session)"
            var s = sess[key] ?? TmuxSession(name: pane.session, server: pane.server, attached: pane.sessionAttached, windows: [])
            if let wi = s.windows.firstIndex(where: { $0.index == pane.windowIndex }) {
                s.windows[wi].panes.append(pane)
            } else {
                s.windows.append(TmuxWindow(index: pane.windowIndex, name: pane.windowName, active: pane.windowActive, panes: [pane]))
            }
            sess[key] = s
        }
        sessions = sess.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
            .map { var s = $0; s.windows.sort { $0.index < $1.index }; return s }
        firstPoll = false
    }

    /// Charge des données fictives (documentation, captures d'écran) sans interroger tmux.
    func loadDemo() {
        let d = DemoData.make()
        agents = d.agents
        sessions = d.sessions
        history = d.history
        tmuxRunning = true
    }

    func record(_ a: Agent) {
        if let last = history.first, last.paneID == a.id, last.waiting == (a.state == .waiting),
           Date().timeIntervalSince(last.date) < 5 { return }
        let e = HistoryEntry(paneID: a.id, session: a.pane.session, windowIndex: a.pane.windowIndex,
                             windowName: a.pane.windowName, project: a.pane.project, agentName: a.displayName,
                             waiting: a.state == .waiting, date: Date())
        history = Array(([e] + history).prefix(30))
        if !DemoMode.active, let d = try? JSONEncoder().encode(history) { UserDefaults.standard.set(d, forKey: "history") }
    }

    /// Pane actuel correspondant à une entrée (même pane, sinon la fenêtre) ; nil si la session n'existe plus.
    func target(for e: HistoryEntry) -> Pane? {
        let all = sessions.flatMap(\.windows).flatMap(\.panes)
        if let p = all.first(where: { $0.id == e.paneID && $0.session == e.session }) { return p }
        return sessions.first { $0.name == e.session && $0.server == all.first(where: { $0.id == e.paneID })?.server }?.windows.first { $0.index == e.windowIndex }?.activePane
    }

    func state(ofWindow w: TmuxWindow) -> AgentState? {
        agents.filter { a in w.panes.contains(where: { $0.id == a.id }) }.map(\.state).min(by: { $0.priority < $1.priority })
    }
}
