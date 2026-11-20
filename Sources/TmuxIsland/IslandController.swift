import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    @Published var contentHeight: CGFloat = 0
    @Published var flashPane: String?
    /// Agent qui vient de finir : l'île compacte s'élargit pour l'annoncer quelques secondes.
    @Published var toast: Agent?
    @Published var historyOpen = false
    /// Pane dont l'aperçu de l'écran est déplié (survol d'une ligne).
    @Published var hoveredPane: String?
    /// Zones des lignes d'agents (coordonnées de l'île, origine en haut à gauche), publiées par la vue.
    var rowFrames: [String: CGRect] = [:]
    private var hoverWork: DispatchWorkItem?
    private var requestedRow: String?

    /// Le survol vient de la position réelle du curseur (pas de `onHover`, qui émet de faux
    /// « sorti / entré » quand la fenêtre se redimensionne sous le curseur et fait boucler l'aperçu).
    func setHoveredRow(_ id: String?) {
        guard id != requestedRow else { return }
        requestedRow = id
        hoverWork?.cancel()
        if let id {
            if hoveredPane == id { return }
            let w = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.2)) { self?.hoveredPane = id }
            }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: w)
        } else if hoveredPane != nil {
            let w = DispatchWorkItem { [weak self] in
                withAnimation(.easeOut(duration: 0.15)) { self?.hoveredPane = nil }
            }
            hoverWork = w
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: w)
        }
    }

    func resetHover() {
        hoverWork?.cancel()
        requestedRow = nil
        hoveredPane = nil
    }
    /// Mode concentration : plus de son, de toast ni de bannière — seuls les points d'état restent.
    @Published var focusMode = UserDefaults.standard.bool(forKey: "focusMode")
    var onToggleFocus: (() -> Void)?
    var notchW: CGFloat = 190
    var notchH: CGFloat = 32
    var hasActivity = false
    let wing: CGFloat = 74
    let expandedW: CGFloat = 600
    var compactW: CGFloat { notchW + 2 * (toast == nil ? wing : toastWing) }
    let toastWing: CGFloat = 150
    var requestKey: (() -> Void)?
    var onJump: ((Agent) -> Void)?
    var onJumpPane: ((Pane) -> Void)?
    var onTapCompact: (() -> Void)?
}

final class IslandPanel: NSPanel {
    var onKey: ((NSEvent) -> Bool)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !(firstResponder is NSText), onKey?(event) == true { return }
        super.sendEvent(event)
    }
}

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

    // MARK: - Géométrie

    /// Option « suivre l'écran actif » : l'île se pose sur l'écran où se trouve le curseur.
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
        model.requestKey = { [weak self] in self?.panel.makeKey() }
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

    /// La fenêtre garde une taille FIXE (assez grande pour l'île dépliée) : la redimensionner pendant
    /// l'animation décrochait l'île du haut de l'écran (une bande vide laissait voir le fond).
    /// Seule la zone visible de l'île capte la souris (voir `ignoresMouseEvents`).
    private func updateFrame(animated: Bool) {
        let h = min(820, screen.frame.height - 40)
        let target = NSRect(x: screen.frame.midX - model.expandedW / 2, y: screen.frame.maxY - h,
                            width: model.expandedW, height: h)
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    /// Rectangle réellement dessiné par l'île (coordonnées écran), centré en haut de l'écran.
    private func visibleRect() -> NSRect {
        let w = model.expanded ? model.expandedW : model.compactW
        let h = model.expanded ? max(model.contentHeight, model.notchH + 60) : model.notchH
        return NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
    }

    // MARK: - État

    private func bind() {
        store.$agents.receive(on: RunLoop.main).sink { [weak self] agents in
            guard let self else { return }
            self.model.hasActivity = agents.contains { $0.state != .idle }
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

    func setExpanded(_ value: Bool) {
        guard model.expanded != value else { return }
        if !value { model.resetHover() }
        if value { model.toast = nil }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.expanded = value }
        updateFrame(animated: true)
    }

    /// Debug : joue un survol dans la vraie fenêtre et enregistre le contenu image par image.
    func debugAnimTest(dir: String) {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        setExpanded(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [self] in
            let target = store.visibleAgents.max(by: { $0.screen.count < $1.screen.count })
            var n = 0
            Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [self] t in
                if n == 5 { model.setHoveredRow(target?.id) }
                if n == 70 { model.setHoveredRow(nil) }
                if let v = panel.contentView, let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    let name = String(format: "%@/f%03d_w%dx%d.png", dir, n, Int(panel.frame.width), Int(panel.frame.height))
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: name))
                }
                n += 1
                if n > 110 { t.invalidate() }
            }
        }
    }

    func toggle() {
        if model.expanded && pinned {
            pinned = false
            setExpanded(false)
        } else {
            pinned = true
            setExpanded(true)
            panel.makeKey()
        }
    }

    func toggleFocus() {
        model.focusMode.toggle()
        UserDefaults.standard.set(model.focusMode, forKey: "focusMode")
        // En quittant la concentration, on annonce ce qui s'est accumulé.
        if !model.focusMode, let next = store.nextAttention() { notify(next) }
    }

    private func notify(_ agent: Agent) {
        if model.focusMode { return }
        NSSound(named: agent.state == .waiting ? "Funk" : "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        model.flashPane = agent.id
        // L'île est sur l'écran de la notch : si l'utilisateur travaille ailleurs, on le prévient là où il regarde.
        if let current = screenUnderMouse(), current != screen {
            if followScreen {
                apply(screen: current)
                updateFrame(animated: false)
            } else {
                banner.show(agent, on: current)
            }
        }
        // Toast dans l'île compacte (cliquable) ; si l'île est déjà dépliée, la ligne clignote simplement.
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
        setExpanded(false)
    }

    func jumpToNextAttention() {
        if let a = store.nextAttention() { jump(to: a) } else { toggle() }
    }

    // MARK: - Souris & clavier

    private func installMouseMonitors() {
        let handler: (NSEvent) -> Void = { [weak self] _ in Task { @MainActor in self?.mouseMoved() } }
        NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved], handler: handler)
        NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved]) { e in handler(e); return e }
    }

    private func mouseMoved() {
        let loc = NSEvent.mouseLocation
        // Mode « suivre l'écran actif » : après un court délai sur un autre écran, l'île vient s'y poser.
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
            // Île compacte : zone de survol un peu élargie (côtés et bord haut de l'écran).
            area = NSRect(x: area.minX - 6, y: area.minY, width: area.width + 12, height: area.height + 6)
        }
        let inside = area.contains(loc)
        // Hors de l'île, la fenêtre (transparente et plus grande) laisse passer les clics.
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
        if let n = Int(ch), n >= 1, n <= visible.count { jump(to: visible[n - 1]); return true }
        return false
    }
}
