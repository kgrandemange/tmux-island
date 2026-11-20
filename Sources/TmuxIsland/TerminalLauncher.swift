import AppKit
import Foundation

/// Ouvre un terminal qui s'attache à une session tmux (quand aucun client n'est affiché), pour les terminaux courants.
enum TerminalLauncher {
    enum Launch: Equatable {
        case process(String, [String])
        case appleScript(String)
    }

    static let knownBundles = [
        "com.github.wez.wezterm", "com.mitchellh.ghostty", "com.googlecode.iterm2",
        "net.kovidgoyal.kitty", "org.alacritty", "com.apple.Terminal",
    ]

    /// Commande à lancer pour exécuter `argv` dans un nouveau terminal `bundleID`.
    static func launch(bundleID: String, argv: [String]) -> Launch {
        let command = argv.map(shellQuote).joined(separator: " ")
        switch bundleID {
        case "com.googlecode.iterm2":
            return .appleScript("""
            tell application "iTerm2"
              activate
              create window with default profile command "\(appleScriptEscape(command))"
            end tell
            """)
        case "com.github.wez.wezterm":
            return .process("/usr/bin/open", ["-n", "-b", bundleID, "--args", "start", "--"] + argv)
        case "com.mitchellh.ghostty", "org.alacritty":
            return .process("/usr/bin/open", ["-n", "-b", bundleID, "--args", "-e"] + argv)
        case "net.kovidgoyal.kitty":
            return .process("/usr/bin/open", ["-n", "-b", bundleID, "--args"] + argv)
        default: // Terminal.app et terminaux sans CLI connue
            return .appleScript("""
            tell application "Terminal"
              activate
              do script "\(appleScriptEscape(command))"
            end tell
            """)
        }
    }

    static func shellQuote(_ s: String) -> String {
        s.range(of: "^[A-Za-z0-9_/.:=@%+-]+$", options: .regularExpression) != nil
            ? s : "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    static func appleScriptEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// Terminal à utiliser : le dernier vu avec un client tmux, sinon un terminal déjà ouvert, sinon un installé.
    static func preferredBundle() -> String {
        func installed(_ id: String) -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) != nil }
        if let last = UserDefaults.standard.string(forKey: "lastTerminalBundle"), installed(last) { return last }
        if let running = knownBundles.first(where: { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }) {
            return running
        }
        return knownBundles.first(where: installed) ?? "com.apple.Terminal"
    }

    static func attach(session: String, server: String?) {
        var argv = [TmuxService.path]
        if let server { argv += ["-S", server] }
        argv += ["attach-session", "-t", "=\(session)"]
        switch launch(bundleID: preferredBundle(), argv: argv) {
        case let .process(exe, args): Shell.run(exe, args)
        case let .appleScript(src): Shell.run("/usr/bin/osascript", ["-e", src])
        }
    }
}
