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
    let id: String            // unique entre serveurs : « %12 » (serveur par défaut) ou « socket:%12 »
    let tmuxID: String        // identifiant tmux brut (« %12 »), pour les commandes
    let server: String?       // chemin du socket tmux (nil = serveur par défaut)
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
    /// Clé de correspondance avec `~/.claude/sessions/*.json` (champ `tmux` : « session:@fenêtre.%pane »).
    var claudeKey: String { "\(session)|\(tmuxID)" }
}

struct Agent: Identifiable, Equatable {
    var pane: Pane
    var kind: String
    var state: AgentState
    var since: Date
    var message: String?
    var tail: [String]
    /// Dernières lignes de l'écran du pane, affichées au survol.
    var screen: [String] = []
    /// Contexte de la session Claude Code (nil pour les autres agents ou si introuvable).
    var usage: ClaudeUsage.Info?

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

/// Une fin d'agent (terminé / en attente), conservée pour retrouver ce qu'on a raté.
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
    /// Les sessions d'un serveur tmux secondaire (`tmux -L nom`) sont suffixées par le nom du socket.
    var displayName: String { server.map { "\(name) (\(($0 as NSString).lastPathComponent))" } ?? name }
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
