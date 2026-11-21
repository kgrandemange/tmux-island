import AppKit
import Carbon
import Combine

/// Global keyboard shortcut (Carbon modifier masks: no accessibility permission required).
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var label: String {
        var s = ""
        if modifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { s += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { s += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { s += "⌘" }
        return s + (Self.keyNames[keyCode] ?? "#\(keyCode)")
    }

    static func carbonModifiers(_ f: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if f.contains(.control) { m |= UInt32(controlKey) }
        if f.contains(.option) { m |= UInt32(optionKey) }
        if f.contains(.shift) { m |= UInt32(shiftKey) }
        if f.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// A global shortcut must include at least ⌃, ⌥ or ⌘ (otherwise it would steal normal typing).
    var isValidGlobal: Bool { modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 }

    static let keyNames: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12",
        0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H", 34: "I", 38: "J", 40: "K", 37: "L",
        46: "M", 45: "N", 31: "O", 35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V", 13: "W",
        7: "X", 16: "Y", 6: "Z",
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        27: "-", 24: "=", 33: "[", 30: "]", 41: ";", 39: "'", 43: ",", 47: ".", 44: "/", 42: "\\", 50: "`",
    ]
}

enum ShortcutAction: String, CaseIterable, Codable {
    case toggle, next, focus

    var title: String {
        switch self {
        case .toggle: return L10n.tr("shortcut.toggle")
        case .next: return L10n.tr("shortcut.next")
        case .focus: return L10n.tr("shortcut.focus")
        }
    }

    var defaultShortcut: Shortcut {
        let mods = UInt32(controlKey | optionKey)
        switch self {
        case .toggle: return Shortcut(keyCode: UInt32(kVK_Space), modifiers: mods)
        case .next: return Shortcut(keyCode: UInt32(kVK_ANSI_J), modifiers: mods)
        case .focus: return Shortcut(keyCode: UInt32(kVK_ANSI_F), modifiers: mods)
        }
    }
}

@MainActor
final class ShortcutStore: ObservableObject {
    static let shared = ShortcutStore()
    @Published private(set) var shortcuts: [ShortcutAction: Shortcut]
    private let key = "shortcuts"

    init() {
        var loaded: [ShortcutAction: Shortcut] = [:]
        if let d = UserDefaults.standard.data(forKey: key),
           let raw = try? JSONDecoder().decode([String: Shortcut].self, from: d) {
            for (k, v) in raw { if let a = ShortcutAction(rawValue: k) { loaded[a] = v } }
        }
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, loaded[$0] ?? $0.defaultShortcut) })
    }

    func shortcut(_ a: ShortcutAction) -> Shortcut { shortcuts[a] ?? a.defaultShortcut }

    /// Rejects a shortcut with no modifier or already used by another action; returns the reason for the refusal.
    @discardableResult
    func set(_ s: Shortcut, for a: ShortcutAction) -> String? {
        guard s.isValidGlobal else { return L10n.tr("shortcut.error.modifier") }
        if let other = ShortcutAction.allCases.first(where: { $0 != a && shortcut($0) == s }) {
            return L10n.tr("shortcut.error.used", other.title)
        }
        shortcuts[a] = s
        persist()
        return nil
    }

    func resetAll() {
        shortcuts = Dictionary(uniqueKeysWithValues: ShortcutAction.allCases.map { ($0, $0.defaultShortcut) })
        persist()
    }

    private func persist() {
        let raw = Dictionary(uniqueKeysWithValues: shortcuts.map { ($0.key.rawValue, $0.value) })
        if let d = try? JSONEncoder().encode(raw) { UserDefaults.standard.set(d, forKey: key) }
    }
}
