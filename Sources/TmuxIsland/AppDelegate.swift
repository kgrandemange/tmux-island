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

        // Global shortcuts (configurable in the settings): re-registered on every change.
        registerHotKeys()
        shortcutSub = ShortcutStore.shared.$shortcuts.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.registerHotKeys() }
        }
        settings.model.onFollowScreen = { [weak self] on in self?.controller.setFollowScreen(on) }
        settings.model.onLaunchAtLogin = { [weak self] on in self?.setLaunchAtLogin(on) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.topthird.inset.filled", accessibilityDescription: "TmuxIsland")
        let menu = NSMenu()
        toggleItem = menu.addItem(withTitle: L10n.tr("menu.open"), action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        nextItem = menu.addItem(withTitle: L10n.tr("menu.next"), action: #selector(next), keyEquivalent: "")
        nextItem.target = self
        focusItem = menu.addItem(withTitle: L10n.tr("menu.focus"), action: #selector(toggleFocus), keyEquivalent: "")
        focusItem.target = self
        focusItem.state = controller.model.focusMode ? .on : .off
        focusSub = controller.model.$focusMode.sink { [weak self] on in self?.focusItem.state = on ? .on : .off }
        menu.addItem(.separator())
        followItem = menu.addItem(withTitle: L10n.tr("menu.follow"), action: #selector(toggleFollowScreen), keyEquivalent: "")
        followItem.target = self
        loginItem = menu.addItem(withTitle: L10n.tr("menu.login"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.delegate = self
        let prefs = menu.addItem(withTitle: L10n.tr("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        prefs.target = self
        menu.addItem(withTitle: L10n.tr("menu.stateFolder"), action: #selector(openState), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: L10n.tr("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
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
            alert.messageText = L10n.tr("alert.loginTitle")
            alert.informativeText = L10n.tr("alert.loginBody", error.localizedDescription)
            alert.runModal()
            settings.model.launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let sc = ShortcutStore.shared
        toggleItem.title = "\(L10n.tr("menu.open"))  (\(sc.shortcut(.toggle).label))"
        nextItem.title = "\(L10n.tr("menu.next"))  (\(sc.shortcut(.next).label))"
        focusItem.title = "\(L10n.tr("menu.focus"))  (\(sc.shortcut(.focus).label))"
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
            alert.messageText = L10n.tr("alert.loginTitle")
            alert.informativeText = L10n.tr("alert.loginBody", error.localizedDescription)
            alert.runModal()
        }
    }

    @objc private func toggleFocus() { controller.toggleFocus() }
    @objc private func next() { controller.jumpToNextAttention() }
    @objc private func openState() {
        HookStore.ensureDir()
        NSWorkspace.shared.open(HookStore.dir)
    }
}
