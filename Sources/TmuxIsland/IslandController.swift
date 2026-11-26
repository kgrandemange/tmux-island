import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandController: NSObject {
    let store: AgentStore
    let model = IslandModel()
    private var panel: IslandPanel!
    private let banner = BannerController()
    private var screen: NSScreen = NSScreen.main ?? NSScreen.screens[0]
    private var bag = Set<AnyCancellable>()
    private var pinned = false
    private var hovering = false
    private var expandWork: DispatchWorkItem?
    private var collapseWork: DispatchWorkItem?

    init(store: AgentStore) {
        self.store = store
        super.init()
        refreshGeometry()
        banner.onJump = { [weak self] agent in self?.jump(to: agent) }
        buildPanel()
        bind()
        installMouseMonitors()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshGeometry(); self?.updateFrame(animated: false) }
        }
    }

    // MARK: - Geometry

    /// "Follow the active screen" option: the island settles on the screen where the cursor is.
    private(set) var followScreen = UserDefaults.standard.bool(forKey: "followActiveScreen")
    private var moveWork: DispatchWorkItem?

    func setFollowScreen(_ on: Bool) {
        followScreen = on
        UserDefaults.standard.set(on, forKey: "followActiveScreen")
        refreshGeometry()
        updateFrame(animated: false)
    }

    private func screenUnderMouse() -> NSScreen? {
        NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
    }

    private func refreshGeometry() {
        let notchScreen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        apply(screen: followScreen ? (screenUnderMouse() ?? notchScreen) : notchScreen)
    }

    private func apply(screen newScreen: NSScreen) {
        screen = newScreen
        model.objectWillChange.send()
        if screen.safeAreaInsets.top > 0 {
            model.notchH = screen.safeAreaInsets.top
            let l = screen.auxiliaryTopLeftArea?.width ?? 0
            let r = screen.auxiliaryTopRightArea?.width ?? 0
            model.notchW = (l > 0 && r > 0) ? screen.frame.width - l - r : 190
        } else {
            model.notchH = 30
            model.notchW = 170
        }
    }

    private func buildPanel() {
        panel = IslandPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isMovable = false
        panel.acceptsMouseMovedEvents = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.onKey = { [weak self] e in self?.handleKey(e) ?? false }
        let host = NSHostingView(rootView: IslandView(store: store, model: model))
        host.sizingOptions = []
        panel.contentView = host
        model.requestKey = { [weak self] in self?.takeKey() }
        model.onToggleFocus = { [weak self] in self?.toggleFocus() }
        model.onTapCompact = { [weak self] in
            guard let self else { return }
            if let t = self.model.toast { self.jump(to: t) } else { self.toggle() }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: panel,
                                               queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.pinned = false
                if !self.hovering { self.setExpanded(false) }
            }
        }
        updateFrame(animated: false)
        panel.orderFrontRegardless()
    }

    /// The window keeps a FIXED size (big enough for the expanded island): resizing it during
    /// the animation detached the island from the top of the screen (an empty strip showed the background).
    /// Only the island's visible area captures the mouse (see `ignoresMouseEvents`).
    private func updateFrame(animated: Bool) {
        let h = min(820, screen.frame.height - 40)
        let target = NSRect(x: screen.frame.midX - model.expandedW / 2, y: screen.frame.maxY - h,
                            width: model.expandedW, height: h)
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    /// Rectangle actually drawn by the island (screen coordinates), centered at the top of the screen.
    private func visibleRect() -> NSRect {
        let w = model.expanded ? model.expandedW : model.compactW
        let h = model.expanded ? max(model.contentHeight, model.notchH + 60) : model.notchH
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    // MARK: - State

    private func bind() {
        store.$agents.receive(on: RunLoop.main).sink { [weak self] agents in
            guard let self else { return }
            self.updateFrame(animated: true)
        }.store(in: &bag)

        model.$toast.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateFrame(animated: true) }
        }.store(in: &bag)

        model.$contentHeight.removeDuplicates().sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateFrame(animated: true) }
        }.store(in: &bag)

        store.alerts.receive(on: RunLoop.main).sink { [weak self] agent in
            self?.notify(agent)
        }.store(in: &bag)
    }

    func setExpanded(_ value: Bool, restoreFocus restore: Bool = true) {
        guard model.expanded != value else { return }
        if !value && restore { restoreFocus() }
        if !value { model.resetHover() }
        if value { model.toast = nil }
        // Soft opening with a slight bounce; faster, calmer closing with no bounce.
        let curve: Animation = value ? .timingCurve(0.34, 1.38, 0.5, 1, duration: 0.52)
                                     : .timingCurve(0.4, 0, 0.2, 1, duration: 0.26)
        withAnimation(curve) { model.expanded = value }
        updateFrame(animated: true)
    }

    /// Debug: plays an open/close in the real window and records its content frame by frame.
    func debugAnimTest(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        var n = 0
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [self] t in
            if n == 10 { setExpanded(true) }
            if n == 40 { setExpanded(false) }
            if let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                let name = String(format: "%@/f%03d.png", dir, n)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
            }
            n += 1
            if n > 80 { t.invalidate() }
        }
    }

    func toggle() {
        if model.expanded && pinned {
            pinned = false
            setExpanded(false)
        } else {
            pinned = true
            setExpanded(true)
            takeKey()
        }
    }

    /// App that was frontmost when the island took the keyboard, so Esc can give the focus back to it.
    private var appBeforeKey: NSRunningApplication?

    private func takeKey() {
        if !panel.isKeyWindow {
            let front = NSWorkspace.shared.frontmostApplication
            appBeforeKey = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        }
        panel.makeKey()
    }

    /// Gives the keyboard back to the window the user was in before the island took it.
    private func restoreFocus() {
        defer { appBeforeKey = nil }
        guard panel.isKeyWindow else { return }
        // Ordering the panel out hands the key status back to the previous window; then bring it back on screen.
        panel.orderOut(nil)
        panel.orderFrontRegardless()
        appBeforeKey?.activate()
    }

    func toggleFocus() {
        model.focusMode.toggle()
        UserDefaults.standard.set(model.focusMode, forKey: "focusMode")
        // When leaving focus mode, announce what piled up.
        if !model.focusMode, let next = store.nextAttention() { notify(next) }
    }

    private func notify(_ agent: Agent) {
        if model.focusMode { return }
        if UserDefaults.standard.object(forKey: "soundsEnabled") as? Bool ?? true {
            NSSound(named: agent.state == .waiting ? "Funk" : "Glass")?.play()
        }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        model.flashPane = agent.id
        // The island is on the notch screen: if the user works elsewhere, alert them where they are looking.
        if let current = screenUnderMouse(), current != screen {
            if followScreen {
                apply(screen: current)
                updateFrame(animated: false)
            } else {
                banner.show(agent, on: current)
            }
        }
        // Toast in the compact island (clickable); if the island is already expanded, the row simply flashes.
        if !model.expanded {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.toast = agent }
        }
        collapseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.model.flashPane = nil
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { self.model.toast = nil }
        }
        collapseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: work)
    }

    func jump(to agent: Agent) {
        store.acknowledge(agent.id)
        FocusService.jump(to: agent.pane)
        pinned = false
        setExpanded(false, restoreFocus: false)
    }

    func jumpToNextAttention() {
        if let a = store.nextAttention() { jump(to: a) }
        else if FocusService.focusLastTerminal() { pinned = false; setExpanded(false, restoreFocus: false) }
        else { toggle() }
    }

    // MARK: - Souris & clavier

    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in Task { @MainActor in self?.mouseMoved() } }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in handler(e); return e }
    }

    private func mouseMoved() {
        let loc = NSEvent.mouseLocation
        // "Follow the active screen" mode: after a short delay on another screen, the island moves there.
        if followScreen, !model.expanded, model.toast == nil, let cur = screenUnderMouse(), cur != screen {
            if moveWork == nil {
                let w = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.moveWork = nil
                    if let cur = self.screenUnderMouse(), cur != self.screen, !self.model.expanded {
                        self.apply(screen: cur)
                        self.updateFrame(animated: false)
                    }
                }
                moveWork = w
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
            }
        } else {
            moveWork?.cancel()
            moveWork = nil
        }
        var area = visibleRect()
        if !model.expanded {
            // Compact island: slightly enlarged hover area (sides and top edge of the screen).
            area = NSRect(x: area.minX - 6, y: area.minY, width: area.width + 12, height: area.height + 6)
        }
        let inside = area.contains(loc)
        // Outside the island, the (transparent, larger) window lets clicks through.
        let wantIgnore = !inside
        if panel.ignoresMouseEvents != wantIgnore { panel.ignoresMouseEvents = wantIgnore }
        if model.expanded {
            let f = panel.frame
            let p = CGPoint(x: loc.x - f.minX, y: f.maxY - loc.y)
            model.setHoveredRow(inside ? model.rowFrames.first(where: { $0.value.contains(p) })?.key : nil)
        }
        guard inside != hovering else { return }
        hovering = inside
        if inside {
            collapseWork?.cancel()
            guard !model.expanded else { return }
            expandWork?.cancel()
            let w = DispatchWorkItem { [weak self] in self?.setExpanded(true) }
            expandWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: w)
        } else {
            expandWork?.cancel()
            guard !pinned else { return }
            collapseWork?.cancel()
            let w = DispatchWorkItem { [weak self] in
                guard let self, !self.hovering, !self.pinned else { return }
                self.setExpanded(false)
            }
            collapseWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        }
    }

    private func handleKey(_ e: NSEvent) -> Bool {
        guard model.expanded else { return false }
        if e.keyCode == 53 { // Esc
            pinned = false
            setExpanded(false)
            return true
        }
        guard let ch = e.charactersIgnoringModifiers?.lowercased(), e.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return false }
        if ch == "f" { toggleFocus(); return true }
        if ch == "j" { jumpToNextAttention(); return true }
        let visible = store.visibleAgents
        if let n = Self.agentNumber(forKeyCode: e.keyCode), n <= visible.count { jump(to: visible[n - 1]); return true }
        return false
    }

    /// Physical keys of the number row and the keypad → 1...9. Based on key codes, not characters, so it works on
    /// layouts where digits need Shift (e.g. French AZERTY, where the unshifted key gives `&`, `é`, `"`…).
    nonisolated static func agentNumber(forKeyCode code: UInt16) -> Int? {
        let row: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25]
        let pad: [UInt16] = [83, 84, 85, 86, 87, 88, 89, 91, 92]
        if let i = row.firstIndex(of: code) ?? pad.firstIndex(of: code) { return i + 1 }
        return nil
    }
}
