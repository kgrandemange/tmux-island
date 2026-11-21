import AppKit
import Foundation

struct Snapshot {
    var panes: [Pane] = []
    var kinds: [String: String] = [:]
    var hooks: [String: HookEvent] = [:]
    var tails: [String: [String]] = [:]
    var clients: [TmuxClient] = []
    var terminalPIDs: Set<Int32> = []
    var usage: [String: ClaudeUsage.Info] = [:]
    var claude: [String: ClaudeSession] = [:]
}

/// Gathers everything the store needs from tmux, the process table and the files agents leave behind.
/// Runs off the main thread; it only reads.
enum SnapshotCollector {
    static func collect() -> Snapshot {
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
}
