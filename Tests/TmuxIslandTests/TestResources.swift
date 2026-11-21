import Foundation

enum TestResources {
    /// The repository's `Localization/` folder (tests run unbundled).
    static let localization = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Localization")
}
