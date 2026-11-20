import AppKit
import Foundation

/// Amène l'utilisateur sur le bon pane tmux ET sur la bonne fenêtre/onglet du terminal.
enum FocusService {
    static func jump(to pane: Pane) {
        DispatchQueue.global(qos: .userInitiated).async {
            let client = TmuxService.listClients().max(by: { $0.activity < $1.activity })
            TmuxService.run(["select-window", "-t", "=\(pane.session):\(pane.windowIndex)"])
            TmuxService.run(["select-pane", "-t", pane.id])
            if let client {
                TmuxService.run(["switch-client", "-c", client.tty, "-t", "=\(pane.session)"])
            }
            activateTerminal(for: client)
        }
    }

    static func sendEnter(to pane: Pane) {
        DispatchQueue.global().async { TmuxService.sendKeys(pane.id, keys: ["Enter"]) }
    }

    static func reply(to pane: Pane, text: String) {
        DispatchQueue.global().async {
            TmuxService.sendKeys(pane.id, literal: text)
            TmuxService.sendKeys(pane.id, keys: ["Enter"])
        }
    }

    // MARK: - Terminal

    private static func activateTerminal(for client: TmuxClient?) {
        var bundleID: String?
        if let client {
            let ps = ProcessTable()
            for pid in [client.pid] + ps.ancestors(of: client.pid) {
                if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular {
                    bundleID = app.bundleIdentifier
                    break
                }
            }
        }
        if bundleID == nil {
            let known = ["com.github.wez.wezterm", "com.mitchellh.ghostty", "com.googlecode.iterm2",
                         "net.kovidgoyal.kitty", "org.alacritty", "com.apple.Terminal", "dev.warp.Warp-Stable"]
            bundleID = known.first { !NSRunningApplication.runningApplications(withBundleIdentifier: $0).isEmpty }
        }
        guard let bundleID else { return }

        // Sélection du bon onglet quand le terminal l'expose.
        if let tty = client?.tty {
            switch bundleID {
            case "com.github.wez.wezterm": focusWezTermPane(tty: tty)
            case "com.googlecode.iterm2": runAppleScript(iTermScript(tty: tty))
            case "com.apple.Terminal": runAppleScript(terminalScript(tty: tty))
            default: break
            }
        }
        // Une app « non active » ne peut pas se mettre devant via activate() : `open -b` est fiable.
        Shell.run("/usr/bin/open", ["-b", bundleID])
    }

    private static func focusWezTermPane(tty: String) {
        let candidates = ["/opt/homebrew/bin/wezterm", "/usr/local/bin/wezterm",
                          "/Applications/WezTerm.app/Contents/MacOS/wezterm"]
        guard let bin = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { return }
        let out = Shell.run(bin, ["cli", "list", "--format", "json"]).out
        guard let data = out.data(using: .utf8),
              let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
        if let entry = list.first(where: { ($0["tty_name"] as? String) == tty }), let id = entry["pane_id"] as? Int {
            Shell.run(bin, ["cli", "activate-pane", "--pane-id", String(id)])
        }
    }

    private static func iTermScript(tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  select w
                  tell w to select t
                  select s
                end if
              end repeat
            end repeat
          end repeat
        end tell
        """
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected of t to true
                set index of w to 1
              end if
            end repeat
          end repeat
        end tell
        """
    }

    private static func runAppleScript(_ source: String) {
        Shell.run("/usr/bin/osascript", ["-e", source])
    }
}
