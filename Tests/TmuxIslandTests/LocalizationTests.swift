import XCTest
@testable import TmuxIsland

final class LocalizationTests: XCTestCase {
    override class func setUp() { L10n.resourceRoot = TestResources.localization }

    private func table(_ lang: String, file: String = "Localizable") throws -> [String: String] {
        let url = TestResources.localization.appendingPathComponent("\(lang).lproj/\(file).strings")
        return try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: String])
    }

    func testInfoPlistTextsExistInEveryLanguage() throws {
        for lang in ["en", "fr"] { XCTAssertNotNil(try table(lang, file: "InfoPlist")["NSAppleEventsUsageDescription"]) }
    }

    func testEveryLanguageDefinesTheSameKeys() throws {
        let en = try table("en"), fr = try table("fr")
        XCTAssertFalse(en.isEmpty)
        XCTAssertEqual(Set(en.keys), Set(fr.keys), "a key exists in only one language")
    }

    func testFormatSpecifiersMatchBetweenLanguages() throws {
        let en = try table("en"), fr = try table("fr")
        let spec = try NSRegularExpression(pattern: "%(@|d|%)")
        func specs(_ s: String) -> [String] { spec.matches(in: s, range: NSRange(s.startIndex..., in: s)).map { (s as NSString).substring(with: $0.range) } }
        for (key, value) in en { XCTAssertEqual(specs(value), specs(fr[key] ?? ""), "format mismatch for \(key)") }
    }

    func testNoValueIsEmpty() throws {
        for lang in ["en", "fr"] { for (k, v) in try table(lang) { XCTAssertFalse(v.isEmpty, "\(lang): \(k) is empty") } }
    }

    func testEnglishAndFrenchDiffer() {
        L10n.override = "en"; let en = AgentState.done.label
        L10n.override = "fr"; let fr = AgentState.done.label
        L10n.override = nil
        XCTAssertEqual(en, "done")
        XCTAssertEqual(fr, "terminé")
    }

    func testPluralsAndFormatArguments() {
        defer { L10n.override = nil }
        L10n.override = "en"
        XCTAssertEqual(L10n.plural("empty.idle", 1), "Nothing to handle — 1 idle agent.")
        XCTAssertEqual(L10n.plural("empty.idle", 3), "Nothing to handle — 3 idle agents.")
        XCTAssertEqual(L10n.tr("context.help", "Opus", 200, 42), "Context: Opus / 200k (42%)")
        L10n.override = "fr"
        XCTAssertEqual(L10n.plural("empty.idle", 3), "Rien à traiter — 3 agents inactifs.")
    }

    func testAnUnknownKeyIsShownAsIs() {
        XCTAssertEqual(L10n.tr("no.such.key"), "no.such.key")
    }
}
