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
