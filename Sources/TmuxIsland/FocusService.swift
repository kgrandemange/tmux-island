import AppKit
import Foundation

/// Brings the user to the right tmux pane AND the right terminal window/tab.
enum FocusService {
    static func jump(to pane: Pane) {
        DispatchQueue.global(qos: .userInitiated).async {
            let clients = TmuxService.listClients(server: pane.server)
            TmuxService.run(["select-window", "-t", "=\(pane.session):\(pane.windowIndex)"], server: pane.server)
            TmuxService.run(["select-pane", "-t", pane.tmuxID], server: pane.server)
            // Prefer the client already showing this session (no need to move another terminal), else the most recent one.
            let client = clients.filter { $0.session == pane.session }.max(by: { $0.activity < $1.activity })
                ?? clients.max(by: { $0.activity < $1.activity })
            guard let client else {
                // Detached session: open a terminal that attaches to it.
                TerminalLauncher.attach(session: pane.session, server: pane.server)
                return
            }
            if client.session != pane.session {
                TmuxService.run(["switch-client", "-c", client.tty, "-t", "=\(pane.session)"], server: pane.server)
            }
            activateTerminal(for: client)
        }
    }

    static func sendEnter(to pane: Pane) {
        DispatchQueue.global().async { TmuxService.sendKeys(pane, keys: ["Enter"]) }
    }

    /// Picks an option of the permission menu. Depending on the agent's version, the digit either confirms right away
    /// or only moves the selection: if the menu is still displayed right after, confirm with Enter.
    static func choose(_ option: PermissionOption, on pane: Pane) {
        DispatchQueue.global().async { chooseSync(option, on: pane) }
    }

    static func chooseSync(_ option: PermissionOption, on pane: Pane, settle: TimeInterval = 0.45) {
        TmuxService.sendKeys(pane, literal: String(option.number))
        Thread.sleep(forTimeInterval: settle)
        let stillOpen = Screen.pendingOptions(TmuxService.capture(pane)).contains { $0.number == option.number && $0.selected }
        if stillOpen { TmuxService.sendKeys(pane, keys: ["Enter"]) }
    }

    static func reply(to pane: Pane, text: String) {
        DispatchQueue.global().async {
            TmuxService.sendKeys(pane, literal: text)
            TmuxService.sendKeys(pane, keys: ["Enter"])
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
        UserDefaults.standard.set(bundleID, forKey: "lastTerminalBundle")

        // Select the right tab when the terminal exposes it.
        if let tty = client?.tty, TerminalLauncher.isSafeTTY(tty) {
            switch bundleID {
            case "com.github.wez.wezterm": focusWezTermPane(tty: tty)
            case "com.googlecode.iterm2": runAppleScript(iTermScript(tty: tty))
            case "com.apple.Terminal": runAppleScript(terminalScript(tty: tty))
            default: break
            }
        }
        // An app that is not active cannot bring itself forward with activate(): `open -b` is reliable.
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
                if tty of s is "\(TerminalLauncher.appleScriptEscape(tty))" then
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
              if tty of t is "\(TerminalLauncher.appleScriptEscape(tty))" then
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
