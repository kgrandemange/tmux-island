import XCTest
@testable import TmuxIsland

final class CompactDotsTests: XCTestCase {
    func testEveryAgentGetsADotWhileTheyFit() {
        for n in 0...CompactDots.capacity {
            let l = CompactDots.layout(agentCount: n)
            XCTAssertEqual(l.dots, n)
            XCTAssertNil(l.overflow)
        }
    }

    func testBeyondTheCapacityAFewDotsAndACounterAreShown() {
        let l = CompactDots.layout(agentCount: 7)
        XCTAssertEqual(l.dots, CompactDots.dotsWithCounter)
        XCTAssertEqual(l.overflow, 3)
        XCTAssertEqual(CompactDots.layout(agentCount: 12).overflow, 8)
        XCTAssertEqual(CompactDots.layout(agentCount: 100).overflow, 96)
    }

    func testDotsAndCounterAlwaysAddUpToTheAgentCount() {
        for n in 0...200 {
            let l = CompactDots.layout(agentCount: n)
            XCTAssertEqual(l.dots + (l.overflow ?? 0), n, "count \(n)")
        }
    }

    func testTheCounterIsAtMostThreeCharactersForRealisticFleets() {
        // "+99" is the widest counter the wing is designed for (up to 103 agents).
        XCTAssertLessThanOrEqual("+\(CompactDots.layout(agentCount: 103).overflow ?? 0)".count, 3)
    }

    func testTheOverviewAppearsExactlyWhenTheCompactIslandOverflows() {
        XCTAssertFalse(CompactDots.needsOverview(agentCount: 6))
        XCTAssertTrue(CompactDots.needsOverview(agentCount: 7))
        XCTAssertTrue(CompactDots.needsOverview(agentCount: 15))
    }

    func testNegativeCountsDoNotCrash() {
        XCTAssertEqual(CompactDots.layout(agentCount: -1).dots, 0)
    }
}
