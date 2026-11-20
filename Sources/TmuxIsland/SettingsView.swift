import AppKit
import ServiceManagement
import SwiftUI

/// Réglages modifiables depuis la fenêtre ; chaque changement est répercuté par les closures.
@MainActor
final class SettingsModel: ObservableObject {
    @Published var followScreen = false { didSet { if followScreen != oldValue { onFollowScreen?(followScreen) } } }
    @Published var launchAtLogin = false { didSet { if launchAtLogin != oldValue { onLaunchAtLogin?(launchAtLogin) } } }
    @Published var sounds = true { didSet { if sounds != oldValue { UserDefaults.standard.set(sounds, forKey: "soundsEnabled") } } }
    var onFollowScreen: ((Bool) -> Void)?
    var onLaunchAtLogin: ((Bool) -> Void)?

    func refresh(followScreen: Bool) {
        self.followScreen = followScreen
        launchAtLogin = SMAppService.mainApp.status == .enabled
        sounds = UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true
    }
}

struct SettingsView: View {
    @ObservedObject var shortcuts: ShortcutStore
    @ObservedObject var model: SettingsModel

    var body: some View {
        Form {
            Section("Raccourcis globaux") {
                ForEach(ShortcutAction.allCases, id: \.self) { action in
                    ShortcutRow(action: action, store: shortcuts)
                }
                Button("Rétablir les raccourcis par défaut") { shortcuts.resetAll() }
            }
            Section("Comportement") {
                Toggle("Suivre l'écran actif", isOn: $model.followScreen)
                Toggle("Sons à la fin d'une tâche", isOn: $model.sounds)
                Toggle("Lancer à la connexion", isOn: $model.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
    }
}

private struct ShortcutRow: View {
    let action: ShortcutAction
    @ObservedObject var store: ShortcutStore
    @State private var recording = false
    @State private var error: String?
    @State private var monitor: Any?

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
            }
            Spacer()
            Button(recording ? "Appuie sur la combinaison…" : store.shortcut(action).label) { toggleRecording() }
                .buttonStyle(.bordered)
                .frame(minWidth: 170)
        }
        .onDisappear { stop() }
    }

    private func toggleRecording() {
        recording ? stop() : start()
    }

    private func start() {
        error = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil } // Échap : annuler
            let s = Shortcut(keyCode: UInt32(event.keyCode), modifiers: Shortcut.carbonModifiers(event.modifierFlags))
            error = store.set(s, for: action)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    let model = SettingsModel()

    func show(followScreen: Bool) {
        model.refresh(followScreen: followScreen)
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(shortcuts: .shared, model: model))
            let w = NSWindow(contentViewController: host)
            w.title = "Réglages — TmuxIsland"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            host.view.layoutSubtreeIfNeeded()
            w.setContentSize(NSSize(width: 480, height: max(host.view.fittingSize.height, 320)))
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
