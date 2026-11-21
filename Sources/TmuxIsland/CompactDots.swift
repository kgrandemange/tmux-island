import Foundation

/// How the compact island's right wing shows the agents: one dot each while they fit, otherwise a few dots and a
/// "+N" counter. The wing is narrow (a fixed width shared with the notch), and the rounded corners of the island cut
/// into its last points, so the numbers below keep a safety margin.
enum CompactDots {
    /// Dots that fit side by side with no counter.
    static let capacity = 6
    /// Dots kept next to the "+N" counter once the agents no longer fit.
    static let dotsWithCounter = 4

    /// `dots` agents are drawn; `overflow` (when not nil) is the number shown in the "+N" counter.
    static func layout(agentCount: Int) -> (dots: Int, overflow: Int?) {
        guard agentCount > capacity else { return (max(agentCount, 0), nil) }
        return (dotsWithCounter, agentCount - dotsWithCounter)
    }

    /// The compact island cannot show every agent: the expanded island then lists them all as dots.
    static func needsOverview(agentCount: Int) -> Bool { layout(agentCount: agentCount).overflow != nil }
}

/// Sizes of the expanded island that depend on how many agents and sessions there are. The window is fixed
/// (see `IslandController.updateFrame`), so the content must stay below its height whatever the fleet size.
enum IslandLayout {
    /// Sessions listed before the list scrolls.
    static let visibleSessions = 5
    /// Height of one session row plus its spacing, and of the scrolling list.
    static let sessionRowHeight: CGFloat = 27
    static var sessionsListHeight: CGFloat { CGFloat(visibleSessions) * sessionRowHeight - 8 }
    /// Agent rows shown before the list scrolls, and the height of one row plus its spacing.
    static let visibleAgentRows = 6
    static let agentRowHeight: CGFloat = 60
}
