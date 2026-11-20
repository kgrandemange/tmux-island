import AppKit
import Carbon
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = AgentStore()
    private var controller: IslandController!
    private var statusItem: NSStatusItem!
    private var focusItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var followItem: NSMenuItem!
    private var focusSub: AnyCancellable?
    private var shortcutSub: AnyCancellable?
    private var toggleItem: NSMenuItem!
    private var nextItem: NSMenuItem!
    private let settings = SettingsWindowController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = IslandController(store: store)
        controller.model.onJump = { [weak self] agent in self?.controller.jump(to: agent) }
        controller.model.onJumpPane = { [weak self] pane in
            self?.store.acknowledge(pane.id)
            FocusService.jump(to: pane)
            self?.controller.setExpanded(false)
        }
        store.start()
        if let i = CommandLine.arguments.firstIndex(of: "--animtest"), i + 1 < CommandLine.arguments.count {
            controller.debugAnimTest(dir: CommandLine.arguments[i + 1])
        }

        // Raccourcis globaux (modifiables dans les réglages) : réenregistrés à chaque changement.
        registerHotKeys()
        shortcutSub = ShortcutStore.shared.$shortcuts.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.registerHotKeys() }
        }
        settings.model.onFollowScreen = { [weak self] on in self?.controller.setFollowScreen(on) }
        settings.model.onLaunchAtLogin = { [weak self] on in self?.setLaunchAtLogin(on) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "TmuxIsland")
        let menu = NSMenu()
        toggleItem = menu.addItem(withTitle: "Ouvrir l'île", action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        nextItem = menu.addItem(withTitle: "Prochain agent à traiter", action: #selector(next), keyEquivalent: "")
        nextItem.target = self
        focusItem = menu.addItem(withTitle: "Mode concentration", action: #selector(toggleFocus), keyEquivalent: "")
        focusItem.target = self
        focusItem.state = controller.model.focusMode ? .on : .off
        focusSub = controller.model.$focusMode.sink { [weak self] on in self?.focusItem.state = on ? .on : .off }
        menu.addItem(.separator())
        followItem = menu.addItem(withTitle: "Suivre l'écran actif", action: #selector(toggleFollowScreen), keyEquivalent: "")
        followItem.target = self
        loginItem = menu.addItem(withTitle: "Lancer à la connexion", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.delegate = self
        let prefs = menu.addItem(withTitle: "Réglages…", action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(withTitle: "Ouvrir le dossier des états", action: #selector(openState), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quitter", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }

    @objc private func toggle() { controller.toggle() }

    private func registerHotKeys() {
        HotKeyCenter.shared.unregisterAll()
        let store = ShortcutStore.shared
        let actions: [(ShortcutAction, () -> Void)] = [
            (.toggle, { [weak self] in self?.controller.toggle() }),
            (.next, { [weak self] in self?.controller.jumpToNextAttention() }),
            (.focus, { [weak self] in self?.controller.toggleFocus() }),
        ]
        for (action, handler) in actions {
            let s = store.shortcut(action)
            HotKeyCenter.shared.register(keyCode: s.keyCode, modifiers: s.modifiers, handler: handler)
        }
    }

    @objc private func openSettings() { settings.show(followScreen: controller.followScreen) }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement à la connexion"
            alert.informativeText = "\(error.localizedDescription)\n\nInstalle d'abord l'app avec scripts/install.sh (elle doit se trouver dans ~/Applications)."
            alert.runModal()
            settings.model.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let sc = ShortcutStore.shared
        toggleItem.title = "Ouvrir l'île  (\(sc.shortcut(.toggle).label))"
        nextItem.title = "Prochain agent à traiter  (\(sc.shortcut(.next).label))"
        focusItem.title = "Mode concentration  (\(sc.shortcut(.focus).label))"
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        followItem.state = controller.followScreen ? .on : .off
    }

    @objc private func toggleFollowScreen() { controller.setFollowScreen(!controller.followScreen) }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Impossible de modifier le lancement à la connexion"
            alert.informativeText = "\(error.localizedDescription)\n\nInstalle d'abord l'app avec scripts/install.sh (elle doit se trouver dans ~/Applications)."
            alert.runModal()
        }
    }

    @objc private func toggleFocus() { controller.toggleFocus() }
    @objc private func next() { controller.jumpToNextAttention() }
    @objc private func openState() {
        try? FileManager.default.createDirectory(at: HookStore.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(HookStore.dir)
    }
}

// Documentation : `TmuxIsland --demo-images dossier/` rend des captures de l'île avec des données fictives.
if let i = CommandLine.arguments.firstIndex(of: "--demo-images"), i + 1 < CommandLine.arguments.count {
    let dir = CommandLine.arguments[i + 1]
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    MainActor.assumeIsolated {
        let store = AgentStore()
        store.loadDemo()

        @MainActor func backdrop<Content: View>(width: CGFloat, height: CGFloat, @ViewBuilder _ content: () -> Content) -> some View {
            ZStack(alignment: .top) {
                LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.30), Color(red: 0.05, green: 0.36, blue: 0.42),
                                        Color(red: 0.36, green: 0.18, blue: 0.48)], startPoint: .topLeading, endPoint: .bottomTrailing)
                Rectangle().fill(Color.white.opacity(0.10)).frame(height: 24).frame(maxHeight: .infinity, alignment: .top)
                content()
            }
            .frame(width: width, height: height)
        }

        @MainActor func write(_ name: String, _ view: some View) {
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: dir + "/" + name))
                print(name, img.size)
            }
        }

        @MainActor func model(expanded: Bool) -> IslandModel {
            let m = IslandModel()
            m.expanded = expanded
            m.notchH = 32
            m.notchW = 190
            return m
        }

        // Île dépliée
        let m1 = model(expanded: true)
        write("island-expanded.png", backdrop(width: 760, height: 520) {
            IslandView(store: store, model: m1).frame(width: m1.expandedW, height: 490, alignment: .top)
        })

        // Île dépliée, aperçu du pane au survol
        let m2 = model(expanded: true)
        m2.hoveredPane = store.agents.first { $0.state == .working }?.id
        write("island-preview.png", backdrop(width: 760, height: 640) {
            IslandView(store: store, model: m2).frame(width: m2.expandedW, height: 610, alignment: .top)
        })

        // Île compacte
        let m3 = model(expanded: false)
        write("island-compact.png", backdrop(width: 560, height: 90) {
            IslandView(store: store, model: m3).frame(width: m3.compactW, height: m3.notchH, alignment: .top)
        })

        // Toast à la fin d'une tâche
        let m4 = model(expanded: false)
        m4.toast = store.agents.first { $0.state == .done }
        write("island-toast.png", backdrop(width: 560, height: 90) {
            IslandView(store: store, model: m4).frame(width: m4.compactW, height: m4.notchH, alignment: .top)
        })
    }
    exit(0)
}

// Mode debug : `TmuxIsland --snapshot out.png` rend l'île dépliée dans un PNG (sans afficher de fenêtre).
if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
    let out = CommandLine.arguments[i + 1]
    MainActor.assumeIsolated {
        let store = AgentStore()
        let model = IslandModel()
        model.expanded = true
        model.historyOpen = true
        store.start()
        RunLoop.main.run(until: Date().addingTimeInterval(2.5))
        let hi = Int(ProcessInfo.processInfo.environment["HOVER_INDEX"] ?? "0") ?? 0
        model.hoveredPane = store.visibleAgents.indices.contains(hi) ? store.visibleAgents[hi].id : nil
        let renderer = ImageRenderer(content: IslandView(store: store, model: model).frame(width: model.expandedW).fixedSize(horizontal: false, vertical: true).background(Color(white: 0.5)))
        renderer.scale = 2
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("snapshot \(img.size)")
        }
    }
    exit(0)
}

// Options en ligne de commande pour les scripts : --login-status | --enable-login | --disable-login
if let flag = CommandLine.arguments.first(where: { ["--login-status", "--enable-login", "--disable-login"].contains($0) }) {
    do {
        if flag == "--enable-login" { try SMAppService.mainApp.register() }
        if flag == "--disable-login" { try SMAppService.mainApp.unregister() }
    } catch { print("erreur: \(error.localizedDescription)"); exit(1) }
    switch SMAppService.mainApp.status {
    case .enabled: print("enabled")
    case .requiresApproval: print("requiresApproval")
    case .notRegistered: print("notRegistered")
    case .notFound: print("notFound")
    @unknown default: print("unknown")
    }
    exit(0)
}

let app = NSApplication.shared
let delegate = MainActor.assumeIsolated { AppDelegate() }
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
