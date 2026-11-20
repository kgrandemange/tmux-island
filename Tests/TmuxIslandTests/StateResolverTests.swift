import Carbon
import XCTest
@testable import TmuxIsland

final class StateResolverTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func hook(_ state: String, at offset: TimeInterval = 0) -> HookEvent {
        HookEvent(state: state, agent: "claude", ts: t0.timeIntervalSince1970 + offset, message: nil)
    }

    private func resolve(_ old: Track = Track(state: .idle, since: Date(timeIntervalSince1970: 0)),
                         _ configure: (inout Signals) -> Void) -> Track {
        var s = Signals(now: t0)
        configure(&s)
        return StateResolver.resolve(old: old, signals: s)
    }

    // MARK: - Statut officiel de la session

    func testBusyMeansWorking() {
        XCTAssertEqual(resolve { $0.sessionStatus = "busy" }.state, .working)
    }

    func testBusyThenIdleMeansDone() {
        let working = resolve { $0.sessionStatus = "busy" }
        let done = resolve(working) { $0.sessionStatus = "idle" }
        XCTAssertEqual(done.state, .done)
        XCTAssertFalse(done.doneAcked)
    }

    func testFirstSightOfIdleSessionIsIdleNotDone() {
        XCTAssertEqual(resolve { $0.sessionStatus = "idle" }.state, .idle)
    }

    func testDoneStaysUntilAcknowledged() {
        let working = resolve { $0.sessionStatus = "busy" }
        let done = resolve(working) { $0.sessionStatus = "idle" }
        XCTAssertEqual(resolve(done) { $0.sessionStatus = "idle" }.state, .done)
        var acked = done
        acked.doneAcked = true
        XCTAssertEqual(resolve(acked) { $0.sessionStatus = "idle" }.state, .idle)
    }

    func testInterruptionIsNotReportedAsDone() {
        let working = resolve { $0.sessionStatus = "busy" }
        let after = resolve(working) { $0.sessionStatus = "idle"; $0.screenInterrupted = true }
        XCTAssertEqual(after.state, .idle)
    }

    func testPermissionPromptOnScreenMeansWaitingEvenWhenBusy() {
        XCTAssertEqual(resolve { $0.sessionStatus = "busy"; $0.screenWaiting = true }.state, .waiting)
    }

    func testRecentWaitingHookMeansWaiting() {
        let tr = resolve {
            $0.sessionStatus = "busy"
            $0.sessionStatusAt = t0.addingTimeInterval(-5)
            $0.hook = hook("waiting")
        }
        XCTAssertEqual(tr.state, .waiting)
    }

    func testStaleWaitingHookIsIgnored() {
        let tr = resolve {
            $0.sessionStatus = "busy"
            $0.sessionStatusAt = t0
            $0.hook = hook("waiting", at: -30)
        }
        XCTAssertEqual(tr.state, .working)
    }

    func testWaitingThenIdleMeansDone() {
        let waiting = resolve { $0.sessionStatus = "busy"; $0.screenWaiting = true }
        XCTAssertEqual(resolve(waiting) { $0.sessionStatus = "idle" }.state, .done)
    }

    func testUnknownWaitingLikeStatus() {
        XCTAssertEqual(resolve { $0.sessionStatus = "waiting_for_permission" }.state, .waiting)
    }

    func testDoneSinceUsesStatusTimestamp() {
        let working = resolve { $0.sessionStatus = "busy" }
        let done = resolve(working) { $0.sessionStatus = "idle"; $0.sessionStatusAt = t0.addingTimeInterval(-42) }
        XCTAssertEqual(done.since, t0.addingTimeInterval(-42))
    }

    // MARK: - Acquittement automatique

    func testDoneIsAutoAcknowledgedWhenUserIsLookingAtThePane() {
        let working = resolve { $0.sessionStatus = "busy" }
        let after = resolve(working) { $0.sessionStatus = "idle"; $0.userHere = true }
        XCTAssertEqual(after.state, .idle)
        XCTAssertTrue(after.doneAcked)
    }

    func testWaitingIsNotAutoAcknowledged() {
        XCTAssertEqual(resolve { $0.sessionStatus = "busy"; $0.screenWaiting = true; $0.userHere = true }.state, .waiting)
    }

    // MARK: - Sans statut officiel : hooks

    func testHookWorkingRecentMeansWorking() {
        XCTAssertEqual(resolve { $0.hook = hook("working", at: -2) }.state, .working)
    }

    func testHookWorkingWithoutScreenActivityAfterGraceMeansInterrupted() {
        // Esc : aucun hook Stop n'est émis, l'écran ne montre plus « esc to interrupt ».
        XCTAssertEqual(resolve { $0.hook = hook("working", at: -20) }.state, .idle)
    }

    func testHookWorkingWithScreenActivityStaysWorking() {
        XCTAssertEqual(resolve { $0.hook = hook("working", at: -20); $0.screenWorking = true }.state, .working)
    }

    func testHookDoneMeansDoneUntilAcked() {
        XCTAssertEqual(resolve { $0.hook = hook("done") }.state, .done)
        var acked = Track(state: .idle, since: t0)
        acked.ackedHookTS = t0.timeIntervalSince1970
        XCTAssertEqual(resolve(acked) { $0.hook = hook("done") }.state, .idle)
    }

    func testHookDoneButScreenWorkingMeansNewTurn() {
        XCTAssertEqual(resolve { $0.hook = hook("done"); $0.screenWorking = true }.state, .working)
    }

    func testHookWaiting() {
        XCTAssertEqual(resolve { $0.hook = hook("waiting") }.state, .waiting)
    }

    // MARK: - Sans statut ni hook : heuristique d'écran seule

    func testScreenOnlyWorkingThenQuietMeansDone() {
        let working = resolve { $0.screenWorking = true }
        XCTAssertEqual(working.state, .working)
        XCTAssertEqual(resolve(working) { _ in }.state, .done)
    }

    func testScreenOnlyWaiting() {
        XCTAssertEqual(resolve { $0.screenWaiting = true }.state, .waiting)
    }
}

final class ScreenTests: XCTestCase {
    func testWorkingDetection() {
        XCTAssertTrue(Screen.isWorking(["✻ Thinking… (12s · ↑ 1k tokens · esc to interrupt)"]))
        XCTAssertFalse(Screen.isWorking(["❯ ", "? for shortcuts"]))
    }

    func testWaitingDetection() {
        XCTAssertTrue(Screen.isWaiting(["Do you want to proceed?", "❯ 1. Yes", "  2. No"]))
        XCTAssertTrue(Screen.isWaiting(["Continue? (y/n)"]))
        XCTAssertFalse(Screen.isWaiting(["Hello", "world"]))
    }

    func testInterruptedDetection() {
        XCTAssertTrue(Screen.isInterrupted(["⎿ Interrupted · What should Claude do instead?"]))
        XCTAssertFalse(Screen.isInterrupted(["all good"]))
    }

    func testPreviewDropsDecorativeLines() {
        let lines = ["──────────", "hello", "╭────╮", "world"]
        XCTAssertEqual(Screen.preview(lines), ["hello", "world"])
    }
}

final class AgentDetectionTests: XCTestCase {
    func testAgentKindFromCommandLine() {
        XCTAssertEqual(ProcessTable.agentKind(of: "claude --resume"), "claude")
        XCTAssertEqual(ProcessTable.agentKind(of: "/opt/homebrew/bin/codex"), "codex")
        XCTAssertEqual(ProcessTable.agentKind(of: "node /x/node_modules/@anthropic-ai/claude-code/cli.js"), "claude")
        XCTAssertEqual(ProcessTable.agentKind(of: "node /x/@openai/codex/bin/codex.js"), "codex")
        XCTAssertNil(ProcessTable.agentKind(of: "/bin/zsh -l"))
        XCTAssertNil(ProcessTable.agentKind(of: "vim claude-notes.md"))
    }
}

final class TerminalLauncherTests: XCTestCase {
    private let argv = ["/opt/homebrew/bin/tmux", "attach-session", "-t", "=my session"]

    func testWezTermLaunchesANewInstance() {
        XCTAssertEqual(TerminalLauncher.launch(bundleID: "com.github.wez.wezterm", argv: argv),
                       .process("/usr/bin/open", ["-n", "-b", "com.github.wez.wezterm", "--args", "start", "--"] + argv))
    }

    func testGhosttyAndAlacrittyUseDashE() {
        for id in ["com.mitchellh.ghostty", "org.alacritty"] {
            XCTAssertEqual(TerminalLauncher.launch(bundleID: id, argv: argv),
                           .process("/usr/bin/open", ["-n", "-b", id, "--args", "-e"] + argv))
        }
    }

    func testTerminalAppIsTheFallbackAndQuotesTheCommand() {
        guard case let .appleScript(src) = TerminalLauncher.launch(bundleID: "unknown.app", argv: argv) else {
            return XCTFail("AppleScript attendu")
        }
        XCTAssertTrue(src.contains("tell application \"Terminal\""))
        XCTAssertTrue(src.contains("'=my session'"), "les arguments avec espace doivent être protégés")
    }

    func testITermScript() {
        guard case let .appleScript(src) = TerminalLauncher.launch(bundleID: "com.googlecode.iterm2", argv: argv) else {
            return XCTFail("AppleScript attendu")
        }
        XCTAssertTrue(src.contains("create window with default profile command"))
    }

    func testShellQuoting() {
        XCTAssertEqual(TerminalLauncher.shellQuote("=abc"), "=abc")
        XCTAssertEqual(TerminalLauncher.shellQuote("it's"), "'it'\\''s'")
        XCTAssertEqual(TerminalLauncher.appleScriptEscape("a\"b\\c"), "a\\\"b\\\\c")
    }
}

final class ShortcutTests: XCTestCase {
    func testLabelOrdersModifiersLikeMacOS() {
        let s = Shortcut(keyCode: 49, modifiers: UInt32(Carbon.controlKey | Carbon.optionKey))
        XCTAssertEqual(s.label, "⌃⌥Space")
        let all = Shortcut(keyCode: 38, modifiers: UInt32(Carbon.controlKey | Carbon.optionKey | Carbon.shiftKey | Carbon.cmdKey))
        XCTAssertEqual(all.label, "⌃⌥⇧⌘J")
    }

    func testGlobalShortcutNeedsAModifier() {
        XCTAssertFalse(Shortcut(keyCode: 38, modifiers: 0).isValidGlobal)
        XCTAssertFalse(Shortcut(keyCode: 38, modifiers: UInt32(Carbon.shiftKey)).isValidGlobal)
        XCTAssertTrue(Shortcut(keyCode: 38, modifiers: UInt32(Carbon.cmdKey)).isValidGlobal)
    }

    func testCarbonModifiersFromAppKitFlags() {
        XCTAssertEqual(Shortcut.carbonModifiers([.control, .option]), UInt32(Carbon.controlKey | Carbon.optionKey))
    }

    func testDefaultsAreDistinct() {
        let labels = ShortcutAction.allCases.map { $0.defaultShortcut.label }
        XCTAssertEqual(Set(labels).count, labels.count)
    }
}

final class PermissionOptionsTests: XCTestCase {
    func testParsesBoxedClaudeDialog() {
        let screen = [
            "● Bash(rm -rf build)",
            "╭──────────────────────────────────────────────╮",
            "│ Bash command                                 │",
            "│   rm -rf build                               │",
            "│ Do you want to proceed?                      │",
            "│ ❯ 1. Yes                                     │",
            "│   2. Yes, and don't ask again for rm commands│",
            "│   3. No, and tell Claude what to do differently (esc)│",
            "╰──────────────────────────────────────────────╯",
        ]
        let o = Screen.pendingOptions(screen)
        XCTAssertEqual(o.map(\.number), [1, 2, 3])
        XCTAssertEqual(o.map(\.shortLabel), ["Yes", "Yes, always", "No"])
        XCTAssertEqual(o.map(\.selected), [true, false, false])
    }

    func testParsesPlainDialog() {
        let o = Screen.pendingOptions(["Do you want to proceed?", "❯ 1. Yes", "  2. No"])
        XCTAssertEqual(o.map(\.label), ["Yes", "No"])
    }

    func testIgnoresNumberedListInTheConversation() {
        var screen = ["Voici les étapes :", "1. Installer", "2. Configurer", "3. Lancer"]
        screen += Array(repeating: "texte qui suit", count: 10)
        XCTAssertTrue(Screen.pendingOptions(screen).isEmpty)
    }

    func testUsesTheLastBlockWhenSeveralListsAreOnScreen() {
        let screen = ["1. a", "2. b", "texte", "Do you want to?", "❯ 1. Yes", "  2. No"]
        XCTAssertEqual(Screen.pendingOptions(screen).map(\.label), ["Yes", "No"])
    }

    func testSingleNumberedLineIsNotAMenu() {
        XCTAssertTrue(Screen.pendingOptions(["1. seul"]).isEmpty)
    }

    func testSelectionMarkerMoves() {
        let o = Screen.pendingOptions(["Do you want to proceed?", "  1. Yes", "❯ 2. No"])
        XCTAssertEqual(o.map(\.selected), [false, true])
    }
}

/// Envoie de vraies touches dans un serveur tmux privé (ignoré si tmux est absent).
final class ChooseOptionIntegrationTests: XCTestCase {
    private var sock = ""

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: TmuxService.path), "tmux absent")
        sock = NSTemporaryDirectory() + "island-test-\(UUID().uuidString.prefix(8)).sock"
    }

    override func tearDown() {
        if !sock.isEmpty { TmuxService.run(["kill-server"], server: sock) }
    }

    private func startMenu(script: String) -> Pane {
        TmuxService.run(["new-session", "-d", "-s", "t", "-x", "100", "-y", "30", "bash", "-c", script], server: sock)
        let id = TmuxService.run(["list-panes", "-a", "-F", "#{pane_id}"], server: sock).out.trimmingCharacters(in: .whitespacesAndNewlines)
        return Pane(id: "t:\(id)", tmuxID: id, server: sock, session: "t", windowIndex: 0, windowName: "w", paneIndex: 0,
                    path: "/", pid: 0, paneActive: true, windowActive: true, sessionAttached: false)
    }

    private func waitForMenu(_ pane: Pane) throws -> [PermissionOption] {
        for _ in 0..<40 {
            let o = Screen.pendingOptions(TmuxService.capture(pane))
            if !o.isEmpty { return o }
            Thread.sleep(forTimeInterval: 0.1)
        }
        throw XCTSkip("le menu de test ne s'est pas affiché")
    }

    /// Variante 1 : le chiffre valide immédiatement.
    func testDigitThatConfirmsImmediately() throws {
        let pane = startMenu(script: #"printf 'Do you want to proceed?\n❯ 1. Yes\n  2. No\n'; read -rsn1 k; echo "GOT:$k"; sleep 30"#)
        let options = try waitForMenu(pane)
        FocusService.chooseSync(options[1], on: pane, settle: 0.4)
        Thread.sleep(forTimeInterval: 0.3)
        let screen = TmuxService.capture(pane).joined(separator: "\n")
        XCTAssertTrue(screen.contains("GOT:2"), screen)
    }

    /// Variante 2 : le chiffre ne fait que déplacer la sélection, Entrée valide.
    func testDigitThatOnlyMovesTheSelectionNeedsEnter() throws {
        let script = #"""
        sel=1
        draw() { clear; printf 'Do you want to proceed?\n'; [ $sel = 1 ] && printf '❯ 1. Yes\n' || printf '  1. Yes\n'; [ $sel = 2 ] && printf '❯ 2. No\n' || printf '  2. No\n'; }
        draw
        while true; do read -rsn1 k; if [ -z "$k" ]; then echo "FINAL:$sel"; break; fi; sel=$k; draw; done
        sleep 30
        """#
        let pane = startMenu(script: script)
        let options = try waitForMenu(pane)
        FocusService.chooseSync(options[1], on: pane, settle: 0.5)
        Thread.sleep(forTimeInterval: 0.3)
        let screen = TmuxService.capture(pane).joined(separator: "\n")
        XCTAssertTrue(screen.contains("FINAL:2"), screen)
    }
}

final class BackgroundStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func resolve(_ old: Track = Track(state: .idle, since: Date(timeIntervalSince1970: 0)),
                         _ configure: (inout Signals) -> Void) -> Track {
        var s = Signals(now: t0)
        configure(&s)
        return StateResolver.resolve(old: old, signals: s)
    }

    func testShellStatusMeansBackground() {
        XCTAssertEqual(resolve { $0.sessionStatus = "shell" }.state, .background)
    }

    func testWorkingThenShellIsNotReportedAsDone() {
        let working = resolve { $0.sessionStatus = "busy" }
        let bg = resolve(working) { $0.sessionStatus = "shell" }
        XCTAssertEqual(bg.state, .background)
        XCTAssertFalse(bg.state.needsAttention, "aucune alerte quand l'agent passe en arrière-plan")
    }

    func testBackgroundThenIdleIsQuiet() {
        let bg = resolve { $0.sessionStatus = "shell" }
        XCTAssertEqual(resolve(bg) { $0.sessionStatus = "idle" }.state, .idle)
    }

    func testAgentThatWakesUpAndFinishesIsReported() {
        let bg = resolve { $0.sessionStatus = "shell" }
        let working = resolve(bg) { $0.sessionStatus = "busy" }
        XCTAssertEqual(working.state, .working)
        XCTAssertEqual(resolve(working) { $0.sessionStatus = "idle" }.state, .done)
    }

    func testPermissionPromptBeatsBackground() {
        XCTAssertEqual(resolve { $0.sessionStatus = "shell"; $0.screenWaiting = true }.state, .waiting)
    }

    func testBackgroundHasLowerPriorityThanWorkingButIsVisible() {
        XCTAssertGreaterThan(AgentState.background.priority, AgentState.working.priority)
        XCTAssertLessThan(AgentState.background.priority, AgentState.idle.priority)
    }

    func testBackgroundSummaryFromFooter() {
        XCTAssertEqual(Screen.backgroundSummary(["⏵⏵ bypass permissions on · 3 background tasks · ← 1 agent · ↓ to manage"]), "3 tâches de fond")
        XCTAssertEqual(Screen.backgroundSummary(["⏵⏵ 1 background task · ↓ to manage"]), "1 tâche de fond")
    }

    func testBackgroundSummaryFromTurnEndLine() {
        XCTAssertEqual(Screen.backgroundSummary(["✻ Churned for 10m 53s · done 9:09 PM · 2 shells still running"]), "2 shells")
        XCTAssertNil(Screen.backgroundSummary(["rien de spécial", "❯ "]))
    }
}
