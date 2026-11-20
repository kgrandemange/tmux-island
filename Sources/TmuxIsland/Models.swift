import Foundation

enum AgentState: String {
    case waiting, done, working, idle

    /// Plus petit = plus urgent.
    var priority: Int {
        switch self {
        case .waiting: return 0
        case .done: return 1
        case .working: return 2
        case .idle: return 3
        }
    }

    var needsAttention: Bool { self == .waiting || self == .done }
}

struct Pane: Identifiable, Hashable {
    let id: String            // ex: %12
    let session: String
    let windowIndex: Int
    let windowName: String
    let paneIndex: Int
    let path: String
    let pid: Int32
    let paneActive: Bool      // pane active dans sa fenêtre
    let windowActive: Bool    // fenêtre active dans sa session
    let sessionAttached: Bool

    var isFocusedInSession: Bool { paneActive && windowActive }
    var project: String { (path as NSString).lastPathComponent }
    var numericID: String { String(id.dropFirst()) }
}

struct Agent: Identifiable, Equatable {
    var pane: Pane
    var kind: String
    var state: AgentState
    var since: Date
    var message: String?
    var tail: [String]

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
    let attached: Bool
    var windows: [TmuxWindow]
    var id: String { name }
}

struct TmuxClient {
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
