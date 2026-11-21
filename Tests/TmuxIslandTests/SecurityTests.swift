import XCTest
@testable import TmuxIsland

/// Hardening tests: untrusted inputs (files written by other tools, environment, CLI) must never crash the app,
/// escape their directory, or inject into scripts.
final class SecurityTests: XCTestCase {
    private var root: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    private func tempDir() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("tmuxisland-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: d) }
        return d
    }

    // MARK: - Validation helpers

    func testOnlyRealTTYPathsAreAcceptedForAppleScript() {
        XCTAssertTrue(TerminalLauncher.isSafeTTY("/dev/ttys003"))
        XCTAssertFalse(TerminalLauncher.isSafeTTY("/dev/ttys003\" & (do shell script \"id\") & \""))
        XCTAssertFalse(TerminalLauncher.isSafeTTY("/dev/../etc/passwd"))
        XCTAssertFalse(TerminalLauncher.isSafeTTY("ttys003"))
        XCTAssertFalse(TerminalLauncher.isSafeTTY(""))
    }

    func testSessionIDsMustLookLikeUUIDs() {
        XCTAssertTrue(ClaudeUsage.isValidSessionID("7f8b2403-788a-4609-bf48-f7edf0680520"))
        XCTAssertFalse(ClaudeUsage.isValidSessionID("../../etc/passwd"))
        XCTAssertFalse(ClaudeUsage.isValidSessionID("a/b"))
        XCTAssertFalse(ClaudeUsage.isValidSessionID(".."))
        XCTAssertFalse(ClaudeUsage.isValidSessionID(""))
    }

    func testDemoServerNameCannotEscapeTheTmuxDirectory() {
        XCTAssertTrue(DemoMode.isValidName("tmuxisland-demo"))
        XCTAssertFalse(DemoMode.isValidName("../../tmp/evil"))
        XCTAssertFalse(DemoMode.isValidName("a/b"))
        XCTAssertFalse(DemoMode.isValidName(".."))
        XCTAssertFalse(DemoMode.isValidName(""))
    }

    // MARK: - Malformed files written by other tools

    func testMalformedClaudeSessionFilesAreIgnoredWithoutCrashing() throws {
        let dir = try tempDir()
        func write(_ name: String, _ json: String) throws { try json.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8) }
        try write("1.json", #"{"pid": 99999999999999, "sessionId": "7f8b2403-788a-4609-bf48-f7edf0680520", "tmux": "s:@1.%1"}"#)  // pid out of Int32 range
        try write("2.json", #"{"pid": 2, "sessionId": "../../etc/passwd", "tmux": "s:@1.%2"}"#)                                      // path traversal
        try write("3.json", #"{"pid": "three", "sessionId": 7, "tmux": 5}"#)                                                         // wrong types
        try write("4.json", "not json at all")
        try write("5.json", #"{"pid": 5, "sessionId": "11111111-2222-3333-4444-555555555555", "tmux": "good:@1.%5", "status": "busy"}"#)
        let result = ClaudeUsage.sessionsByPane(dir: dir, alive: { _ in true })
        XCTAssertEqual(Array(result.keys), ["good|%5"])
        XCTAssertEqual(result["good|%5"]?.status, "busy")
    }

    // MARK: - The hook script

    private func runHook(_ args: [String], env: [String: String], stdin: String = "{}") throws -> (state: URL, status: Int32) {
        let state = try tempDir()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [root.appendingPathComponent("scripts/tmux-island-hook").path] + args
        var environment = ["PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin", "XDG_STATE_HOME": state.path, "HOME": state.path]
        environment.merge(env) { $1 }
        p.environment = environment
        let input = Pipe()
        p.standardInput = input
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        return (state.appendingPathComponent("tmux-island"), p.terminationStatus)
    }

    private func files(in dir: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    }

    func testHookWritesAPrivateStateFile() throws {
        let (dir, status) = try runHook(["working"], env: ["TMUX_PANE": "%12", "TMUX": "/private/tmp/tmux-501/default,1,0"])
        XCTAssertEqual(status, 0)
        XCTAssertEqual(files(in: dir), ["12.json"])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("12.json"))) as? [String: Any]
        XCTAssertEqual(json?["state"] as? String, "working")
        let perms = try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o700, "the state directory must be private")
    }

    func testHookIgnoresAPaneIdThatIsNotANumber() throws {
        let (dir, _) = try runHook(["working"], env: ["TMUX_PANE": "%../../../evil", "TMUX": "/x/default,1,0"])
        XCTAssertEqual(files(in: dir), [])
        let (dir2, _) = try runHook(["working"], env: ["TMUX_PANE": "%1/../2", "TMUX": "/x/default,1,0"])
        XCTAssertEqual(files(in: dir2), [])
    }

    func testHookIgnoresUnknownStates() throws {
        let (dir, _) = try runHook(["rm -rf /"], env: ["TMUX_PANE": "%3", "TMUX": "/x/default,1,0"])
        XCTAssertEqual(files(in: dir), [])
    }

    func testHookNeverWritesInvalidJSONEvenWithAHostileAgentName() throws {
        let (dir, _) = try runHook(["done", #"x","state":"pwn"#], env: ["TMUX_PANE": "%4", "TMUX": "/x/default,1,0"])
        let json = try JSONSerialization.jsonObject(with: Data(contentsOf: dir.appendingPathComponent("4.json"))) as? [String: Any]
        XCTAssertEqual(json?["state"] as? String, "done")
        XCTAssertEqual(json?["agent"] as? String, "claude")
    }

    func testHookPrefixesNonDefaultServers() throws {
        let (dir, _) = try runHook(["done"], env: ["TMUX_PANE": "%7", "TMUX": "/private/tmp/tmux-501/my-server,1,0"])
        XCTAssertEqual(files(in: dir), ["my-server__7.json"])
    }
}
