import Foundation

/// User-facing strings. They live in `Localization/<language>.lproj/Localizable.strings` and follow the system
/// language (English is the fallback). To add a language, copy `Localization/en.lproj` to `<code>.lproj`, translate
/// the values and list the code in `CFBundleLocalizations` (scripts/bundle.sh).
///
/// `scripts/bundle.sh` copies the folders into the app. SwiftPM's own resource mechanism is deliberately not used: it
/// embeds the absolute path of the build machine in the binary.
enum L10n {
    /// Forces a language (`en`, `fr`…), for tests and for rendering documentation images.
    /// Also read from the `TMUXISLAND_LANG` environment variable. `nil` = follow the system.
    static var override: String? = ProcessInfo.processInfo.environment["TMUXISLAND_LANG"]

    /// Folder holding the `<language>.lproj` directories when the app is not bundled (tests, `swift run`).
    /// Also read from the `TMUXISLAND_RESOURCES` environment variable.
    static var resourceRoot: URL? = ProcessInfo.processInfo.environment["TMUXISLAND_RESOURCES"].map { URL(fileURLWithPath: $0) }

    private static func lproj(_ language: String) -> Bundle? {
        if let path = Bundle.main.path(forResource: language, ofType: "lproj"), let b = Bundle(path: path) { return b }
        if let root = resourceRoot, let b = Bundle(url: root.appendingPathComponent("\(language).lproj")) { return b }
        return nil
    }

    private static func bundle() -> Bundle {
        if let language = override { return lproj(language) ?? lproj("en") ?? Bundle.main }
        if Bundle.main.path(forResource: "en", ofType: "lproj") != nil { return Bundle.main }   // packaged app: macOS picks the language
        for preferred in Locale.preferredLanguages {                                              // unbundled: pick it ourselves
            if let b = lproj(String(preferred.prefix(2))) { return b }
        }
        return lproj("en") ?? Bundle.main
    }

    /// The localized string for `key`, with `String(format:)` arguments. An unknown key is returned as is.
    static func tr(_ key: String, _ args: CVarArg...) -> String {
        let format = bundle().localizedString(forKey: key, value: key, table: nil)
        return args.isEmpty ? format : String(format: format, arguments: args)
    }

    /// Singular / plural variants: `<key>.one` when `count == 1`, `<key>.other` otherwise.
    static func plural(_ key: String, _ count: Int) -> String {
        tr(count == 1 ? "\(key).one" : "\(key).other", count)
    }
}
