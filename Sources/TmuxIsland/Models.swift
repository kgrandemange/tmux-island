import Foundation

enum AgentState: String {
    /// `background`: the agent's turn is over but shells / sub-agents are still running in the background
    /// (Claude Code's `shell` status). The agent may wake up; it is neither "running" nor "done".
    case waiting, done, working, background, idle

    /// Smaller = more urgent.
    var priority: Int {
        switch self {
        case .waiting: return 0
        case .done: return 1
        case .working: return 2
        case .background: return 3
        case .idle: return 4
        }
    }

    var needsAttention: Bool { self == .waiting || self == .done }
}

struct Pane: Identifiable, Hashable {
    let id: String            // unique across servers: "%12" (default server) or "socket:%12"
    let tmuxID: String        // raw tmux id ("%12"), for commands
    let server: String?       // tmux socket path (nil = default server)
    let session: String
    let windowIndex: Int
    let windowName: String
    let paneIndex: Int
    let path: String
    let pid: Int32
    let paneActive: Bool      // active pane in its window
    let windowActive: Bool    // active window in its session
    let sessionAttached: Bool

    var isFocusedInSession: Bool { paneActive && windowActive }
    var project: String { (path as NSString).lastPathComponent }
    /// Matching key with `~/.claude/sessions/*.json` (`tmux` field: "session:@window.%pane").
    var claudeKey: String { "\(session)|\(tmuxID)" }
}

/// A choice offered by a permission menu ("1. Yes", "2. Yes, and don't ask again…", "3. No").
struct PermissionOption: Equatable, Identifiable {
    let number: Int
    let label: String
    let selected: Bool
    var id: Int { number }

    var shortLabel: String {
        let lower = label.lowercased()
        if lower.hasPrefix("yes") {
            return lower.contains("don't ask again") || lower.contains("always") || lower.contains("allow all") ? "Yes, always" : "Yes"
        }
        if lower.hasPrefix("no") { return "No" }
        return label.count > 22 ? String(label.prefix(21)) + "…" : label
    }
}

struct Agent: Identifiable, Equatable {
    var pane: Pane
    var kind: String
    var state: AgentState
    var since: Date
    var message: String?
    var tail: [String]
    /// Last lines of the pane's screen, shown on hover.
    var screen: [String] = []
    /// Claude Code session context (nil for other agents or if not found).
    var usage: ClaudeUsage.Info?
    /// Choices of the permission menu displayed on screen (empty if no menu is pending).
    var options: [PermissionOption] = []
    /// State detail read from the screen (e.g. "2 shells", "3 background tasks" for the `background` state).
    var detail: String?

    var id: String { pane.id }

    var displayName: String {
        switch kind {
        case "claude": return "Claude"
        case "codex": return "Codex"
        case "gemini": return "Gemini"
        case "opencode": return "OpenCode"
        case "aider": return "Aider"
        case "cursor": return "Cursor"
        default: return kind.capitalized
        }
    }

    var preview: String {
        if state == .waiting, let m = message, !m.isEmpty { return m }
        return tail.last ?? ""
    }
}

/// An agent finishing (done / waiting), kept so you can find what you missed.
struct HistoryEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    let paneID: String
    let session: String
    let windowIndex: Int
    let windowName: String
    let project: String
    let agentName: String
    let waiting: Bool
    let date: Date
}

struct TmuxWindow: Identifiable {
    let index: Int
    let name: String
    let active: Bool
    var panes: [Pane]
    var id: Int { index }
    var activePane: Pane { panes.first(where: { $0.paneActive }) ?? panes[0] }
}

struct TmuxSession: Identifiable {
    let name: String
    let server: String?
    let attached: Bool
    var windows: [TmuxWindow]
    var id: String { "\(server ?? "")|\(name)" }
    /// Sessions of a secondary tmux server (`tmux -L name`) get the socket name as a suffix.
    var displayName: String { DemoMode.active ? name : server.map { "\(name) (\(($0 as NSString).lastPathComponent))" } ?? name }
}

struct TmuxClient {
    var server: String? = nil
    let tty: String
    let pid: Int32
    let session: String
    let activity: Int
}

struct HookEvent: Decodable {
    let state: String
    let agent: String?
    let ts: Double
    let message: String?
}
