import Foundation

enum Shell {
    @discardableResult
    static func run(_ exe: String, _ args: [String]) -> (out: String, status: Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: exe)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do { try p.run() } catch { return ("", -1) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), p.terminationStatus)
    }
}

/// Table des processus (ps) pour retrouver les agents IA lancés sous chaque pane
/// et remonter du client tmux jusqu'à l'application terminal.
struct ProcessTable {
    private(set) var cmd: [Int32: String] = [:]
    private(set) var parent: [Int32: Int32] = [:]
    private var children: [Int32: [Int32]] = [:]

    init() {
        let out = Shell.run("/bin/ps", ["-axo", "pid=,ppid=,command="]).out
        for line in out.split(separator: "\n") {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard parts.count == 3, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { continue }
            cmd[pid] = String(parts[2])
            parent[pid] = ppid
            children[ppid, default: []].append(pid)
        }
    }

    func descendants(of pid: Int32) -> [Int32] {
        var result: [Int32] = [], stack: [Int32] = [pid]
        while let cur = stack.popLast() {
            result.append(cur)
            stack.append(contentsOf: children[cur] ?? [])
        }
        return result
    }

    func ancestors(of pid: Int32) -> [Int32] {
        var result: [Int32] = [], cur = pid
        while let p = parent[cur], p > 1, !result.contains(p) {
            result.append(p)
            cur = p
        }
        return result
    }

    private static let names: [String: String] = [
        "claude": "claude", "codex": "codex", "gemini": "gemini", "opencode": "opencode",
        "aider": "aider", "amp": "amp", "cursor-agent": "cursor", "goose": "goose",
    ]

    static func agentKind(of cmdline: String) -> String? {
        let lower = cmdline.lowercased()
        if lower.contains("claude-code") { return "claude" }
        if lower.contains("@openai/codex") { return "codex" }
        if lower.contains("gemini-cli") { return "gemini" }
        for token in cmdline.split(separator: " ").prefix(3) {
            let base = (String(token) as NSString).lastPathComponent.lowercased()
            if let kind = names[base] { return kind }
        }
        return nil
    }

    func agentKind(under pid: Int32) -> String? {
        for p in descendants(of: pid) {
            if let c = cmd[p], let k = Self.agentKind(of: c) { return k }
        }
        return nil
    }
}

enum TmuxService {
    static let path: String = {
        for p in ["/opt/homebrew/bin/tmux", "/usr/local/bin/tmux", "/usr/bin/tmux"]
        where FileManager.default.isExecutableFile(atPath: p) { return p }
        return "/opt/homebrew/bin/tmux"
    }()

    private static let sep = "|~|"

    /// `server` = chemin d'un socket (`tmux -S`) ; nil = serveur par défaut.
    @discardableResult
    static func run(_ args: [String], server: String? = nil) -> (out: String, status: Int32) {
        Shell.run(path, (server.map { ["-S", $0] } ?? []) + args)
    }

    /// Serveur par défaut + tous les sockets présents dans le dossier de tmux (`tmux -L nom`, `-S chemin`…).
    static func discoverServers() -> [String?] {
        if let demo = DemoMode.socketPath { return [demo] }
        var servers: [String?] = [nil]
        let uid = getuid()
        var roots = ["/private/tmp/tmux-\(uid)", "/tmp/tmux-\(uid)"]
        if let t = ProcessInfo.processInfo.environment["TMUX_TMPDIR"] { roots.append("\(t)/tmux-\(uid)") }
        var seen = Set<String>()
        for root in roots {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [] where name != "default" {
                let path = root + "/" + name
                var st = stat()
                guard stat(path, &st) == 0, (st.st_mode & S_IFMT) == S_IFSOCK,
                      seen.insert((path as NSString).resolvingSymlinksInPath).inserted else { continue }
                servers.append(path)
            }
        }
        return servers
    }

    static func serverName(_ server: String?) -> String { server.map { ($0 as NSString).lastPathComponent } ?? "default" }

    static func listPanes(server: String? = nil) -> [Pane] {
        let fmt = ["#{pane_id}", "#{session_name}", "#{window_index}", "#{window_name}", "#{pane_index}",
                   "#{pane_current_path}", "#{pane_pid}", "#{pane_active}", "#{window_active}", "#{session_attached}"]
            .joined(separator: sep)
        let res = run(["list-panes", "-a", "-F", fmt], server: server)
        guard res.status == 0 else { return [] }
        return res.out.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: sep)
            guard f.count == 10, let wi = Int(f[2]), let pi = Int(f[4]), let pid = Int32(f[6]) else { return nil }
            let uniqueID = server == nil ? f[0] : "\(serverName(server)):\(f[0])"
            return Pane(id: uniqueID, tmuxID: f[0], server: server, session: f[1], windowIndex: wi, windowName: f[3], paneIndex: pi,
                        path: f[5], pid: pid, paneActive: f[7] == "1", windowActive: f[8] == "1",
                        sessionAttached: (Int(f[9]) ?? 0) > 0)
        }
    }

    static func listClients(server: String? = nil) -> [TmuxClient] {
        let fmt = ["#{client_tty}", "#{client_pid}", "#{client_session}", "#{client_activity}"].joined(separator: sep)
        let res = run(["list-clients", "-F", fmt], server: server)
        guard res.status == 0 else { return [] }
        return res.out.split(separator: "\n").compactMap { line in
            let f = line.components(separatedBy: sep)
            guard f.count == 4, let pid = Int32(f[1]) else { return nil }
            return TmuxClient(server: server, tty: f[0], pid: pid, session: f[2], activity: Int(f[3]) ?? 0)
        }
    }

    /// Dernières lignes significatives de l'écran du pane.
    static func capture(_ pane: Pane) -> [String] {
        let res = run(["capture-pane", "-p", "-J", "-t", pane.tmuxID], server: pane.server)
        guard res.status == 0 else { return [] }
        return res.out.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .suffix(40)
            .map { $0 }
    }

    static func sendKeys(_ pane: Pane, literal: String? = nil, keys: [String] = []) {
        if let literal { run(["send-keys", "-t", pane.tmuxID, "-l", literal], server: pane.server) }
        if !keys.isEmpty { run(["send-keys", "-t", pane.tmuxID] + keys, server: pane.server) }
    }
}

enum HookStore {
    static let dir: URL = {
        let base = ProcessInfo.processInfo.environment["XDG_STATE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/state")
        return base.appendingPathComponent("tmux-island")
    }()

    static func readAll(validPanes: Set<String>) -> [String: HookEvent] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: HookEvent] = [:]
        for url in files where url.pathExtension == "json" {
            // « 56.json » (serveur par défaut) ou « socket__56.json » (autre serveur) — écrit par tmux-island-hook.
            let stem = url.deletingPathExtension().lastPathComponent
            let id: String
            if let r = stem.range(of: "__") { id = "\(stem[..<r.lowerBound]):%\(stem[r.upperBound...])" } else { id = "%" + stem }
            guard validPanes.contains(id) else {
                if !validPanes.isEmpty, !DemoMode.active { try? FileManager.default.removeItem(at: url) }
                continue
            }
            if let data = try? Data(contentsOf: url), let ev = try? JSONDecoder().decode(HookEvent.self, from: data) {
                result[id] = ev
            }
        }
        return result
    }
}
