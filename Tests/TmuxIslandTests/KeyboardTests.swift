import XCTest
@testable import TmuxIsland

final class KeyboardTests: XCTestCase {
    func testNumberRowAndKeypadMapToAgentNumbersWhateverTheLayout() {
        XCTAssertEqual([18, 19, 20, 21, 23, 22, 26, 28, 25].map { IslandController.agentNumber(forKeyCode: $0) }, Array(1...9).map { $0 })
        XCTAssertEqual([83, 84, 85, 86, 87, 88, 89, 91, 92].map { IslandController.agentNumber(forKeyCode: $0) }, Array(1...9).map { $0 })
        XCTAssertNil(IslandController.agentNumber(forKeyCode: 29)) // 0
        XCTAssertNil(IslandController.agentNumber(forKeyCode: 3))  // F
    }
}
