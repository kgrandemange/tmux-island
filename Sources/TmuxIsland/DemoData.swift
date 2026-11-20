import Foundation

/// Données fictives pour la documentation et les captures (jamais utilisées en fonctionnement normal).
enum DemoData {
    static func make(now: Date = Date()) -> (agents: [Agent], sessions: [TmuxSession], history: [HistoryEntry]) {
        func pane(_ id: String, _ session: String, _ win: Int, _ name: String, _ path: String, active: Bool = false) -> Pane {
            Pane(id: id, tmuxID: id, server: nil, session: session, windowIndex: win, windowName: name, paneIndex: 0,
                 path: path, pid: 0, paneActive: true, windowActive: active, sessionAttached: true)
        }
        let web = pane("%1", "web", 2, "checkout-ui", "/Users/demo/shop-web")
        let api = pane("%2", "api", 1, "payments", "/Users/demo/shop-api", active: true)
        let infra = pane("%3", "infra", 1, "terraform", "/Users/demo/shop-infra", active: true)

        let permissionScreen = [
            "● Bash(npm run build && npm test)",
            "  ⎿  Running…",
            "Bash command",
            "  npm run build && npm test",
            "Do you want to proceed?",
            "❯ 1. Yes",
            "  2. Yes, and don't ask again for npm commands",
            "  3. No, and tell Claude what to do differently (esc)",
        ]
        let workingScreen = [
            "● Update(src/invoice/totals.ts)",
            "  ⎿  Updated src/invoice/totals.ts with 6 additions and 2 removals",
            "● Bash(npm test -- invoice)",
            "  ⎿  PASS  src/invoice/totals.test.ts (12 tests)",
            "     Tests: 12 passed, 12 total",
            "● Read(src/invoice/discounts.ts)",
            "✻ Refactoring invoice totals… (1m 12s · ↓ 4.1k tokens)",
            "❯",
            "▸▸ accept edits on (shift+tab to cycle) · esc to interrupt",
        ]
        let doneScreen = [
            "Apply complete! Resources: 3 added, 1 changed, 0 destroyed.",
            "✔ Staging environment is up to date.",
            "❯",
        ]

        let agents = [
            Agent(pane: web, kind: "claude", state: .waiting, since: now.addingTimeInterval(-42),
                  message: "Claude needs your permission to use Bash", tail: [], screen: permissionScreen,
                  usage: ClaudeUsage.Info(tokens: 182_000, window: 1_000_000, model: "claude-sonnet-5-5"),
                  options: Screen.pendingOptions(permissionScreen)),
            Agent(pane: infra, kind: "codex", state: .done, since: now.addingTimeInterval(-130),
                  message: nil, tail: ["✔ Staging environment is up to date."], screen: doneScreen),
            Agent(pane: api, kind: "claude", state: .working, since: now.addingTimeInterval(-72),
                  message: nil, tail: ["✻ Refactoring invoice totals… (1m 12s · ↓ 4.1k tokens)"], screen: workingScreen,
                  usage: ClaudeUsage.Info(tokens: 640_000, window: 1_000_000, model: "claude-sonnet-5-5")),
        ]

        func window(_ session: String, _ items: [(Int, String)], active: Int) -> [TmuxWindow] {
            items.map { i, n in
                TmuxWindow(index: i, name: n, active: i == active,
                           panes: [agents.map(\.pane).first { $0.session == session && $0.windowIndex == i }
                                   ?? pane("%\(100 + i)", session, i, n, "/Users/demo")])
            }
        }
        let sessions = [
            TmuxSession(name: "api", server: nil, attached: true, windows: window("api", [(1, "payments"), (2, "tests"), (3, "logs")], active: 1)),
            TmuxSession(name: "infra", server: nil, attached: true, windows: window("infra", [(1, "terraform"), (2, "k9s")], active: 1)),
            TmuxSession(name: "web", server: nil, attached: true, windows: window("web", [(1, "editor"), (2, "checkout-ui"), (3, "storybook"), (4, "e2e")], active: 2)),
        ]
        let history = [
            HistoryEntry(paneID: "%3", session: "infra", windowIndex: 1, windowName: "terraform", project: "shop-infra",
                         agentName: "Codex", waiting: false, date: now.addingTimeInterval(-130)),
            HistoryEntry(paneID: "%2", session: "api", windowIndex: 1, windowName: "payments", project: "shop-api",
                         agentName: "Claude", waiting: false, date: now.addingTimeInterval(-900)),
        ]
        return (agents, sessions, history)
    }
}
