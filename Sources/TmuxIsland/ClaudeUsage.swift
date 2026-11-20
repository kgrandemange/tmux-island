import Foundation

struct ClaudeSession: Equatable {
    let sessionId: String
    let status: String?
    let statusUpdatedAt: Date?
    let name: String?
}

/// Remplissage du contexte d'une session Claude Code, lu en lecture seule :
/// - `~/.claude/sessions/<pid>.json` relie un pane tmux à une session (champ `tmux`) ;
/// - le transcript `~/.claude/projects/*/<session>.jsonl` donne l'usage du dernier message de l'assistant.
enum ClaudeUsage {
    struct Info: Equatable {
        let tokens: Int
        let window: Int
        let model: String
        var fraction: Double { min(1, Double(tokens) / Double(max(window, 1))) }
    }

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static var transcriptCache: [String: URL] = [:]
    private static var tailCache: [String: (mtime: Date, size: Int, info: Info?)] = [:]

    /// « session|%pane » → session Claude (id, statut, nom), pour les processus encore vivants.
    static func sessionsByPane(alive: (Int32) -> Bool) -> [String: ClaudeSession] {
        let dir = home.appendingPathComponent(".claude/sessions")
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var best: [String: (s: ClaudeSession, started: Double)] = [:]
        for f in files where f.pathExtension == "json" {
            guard let d = try? Data(contentsOf: f),
                  let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let tmux = j["tmux"] as? String, let sid = j["sessionId"] as? String,
                  let pid = j["pid"] as? Int, alive(Int32(pid)),
                  let r = tmux.range(of: ".%", options: .backwards) else { continue }
            guard let colon = tmux.firstIndex(of: ":") else { continue }
            let pane = "\(tmux[..<colon])|%\(tmux[r.upperBound...])"
            let started = (j["startedAt"] as? Double) ?? 0
            let at = (j["statusUpdatedAt"] as? Double).map { Date(timeIntervalSince1970: $0 / 1000) }
            let s = ClaudeSession(sessionId: sid, status: j["status"] as? String, statusUpdatedAt: at, name: j["name"] as? String)
            if best[pane] == nil || started > best[pane]!.started { best[pane] = (s, started) }
        }
        return best.mapValues(\.s)
    }

    static func info(sessionId: String) -> Info? {
        guard let url = transcript(for: sessionId),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let mtime = attrs[.modificationDate] as? Date, let size = attrs[.size] as? Int else { return nil }
        if let c = tailCache[sessionId], c.mtime == mtime, c.size == size { return c.info }
        let info = readTail(url, size: size)
        tailCache[sessionId] = (mtime, size, info)
        return info
    }

    private static func transcript(for sid: String) -> URL? {
        if let u = transcriptCache[sid], FileManager.default.fileExists(atPath: u.path) { return u }
        let projects = home.appendingPathComponent(".claude/projects")
        for d in (try? FileManager.default.contentsOfDirectory(at: projects, includingPropertiesForKeys: nil)) ?? [] {
            let u = d.appendingPathComponent(sid + ".jsonl")
            if FileManager.default.fileExists(atPath: u.path) { transcriptCache[sid] = u; return u }
        }
        return nil
    }

    /// Dernier message de l'assistant (hors sous-agents) : jetons d'entrée + cache = taille du contexte.
    private static func readTail(_ url: URL, size: Int) -> Info? {
        guard let fh = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? fh.close() }
        for limit in [300_000, 1_500_000, 12_000_000] {
            let start = max(0, size - limit)
            try? fh.seek(toOffset: UInt64(start))
            guard let data = try? fh.readToEnd() else { return nil }
            for line in String(decoding: data, as: UTF8.self).split(separator: "\n").reversed()
            where line.contains("\"type\":\"assistant\"") && line.contains("\"usage\"") {
                guard let d = line.data(using: .utf8),
                      let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                      (j["isSidechain"] as? Bool) != true,
                      let m = j["message"] as? [String: Any], let model = m["model"] as? String, !model.hasPrefix("<"),
                      let u = m["usage"] as? [String: Any] else { continue }
                let tokens = (u["input_tokens"] as? Int ?? 0) + (u["cache_read_input_tokens"] as? Int ?? 0)
                    + (u["cache_creation_input_tokens"] as? Int ?? 0)
                guard tokens > 0 else { continue }
                return Info(tokens: tokens, window: window(for: model), model: model)
            }
            if start == 0 { break }
        }
        return nil
    }

    /// La taille de fenêtre n'est pas écrite dans le transcript : heuristique sur le nom du modèle,
    /// ajustable avec `defaults write io.github.kgrandemange.tmux-island contextWindow -int 200000`.
    static func window(for model: String) -> Int {
        if let o = UserDefaults.standard.object(forKey: "contextWindow") as? Int, o > 0 { return o }
        let m = model.lowercased()
        if m.contains("[1m]") { return 1_000_000 }
        if m.contains("haiku") { return 200_000 }
        if m.contains("-5-") || m.contains("-5.") { return 1_000_000 }
        return 200_000
    }
}
