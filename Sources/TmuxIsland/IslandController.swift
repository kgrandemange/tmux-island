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
    var notchW: CGFloat = 190
    var notchH: CGFloat = 32
    var hasActivity = false
    let wing: CGFloat = 74
    let expandedW: CGFloat = 560
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
    private var shrinkWork: DispatchWorkItem?

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

    private func refreshGeometry() {
        screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
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
        panel.onKey = { [weak self] e in self?.handleKey(e) ?? false }
        let host = NSHostingView(rootView: IslandView(store: store, model: model))
        host.sizingOptions = []
        panel.contentView = host
        model.requestKey = { [weak self] in self?.panel.makeKey() }
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

    private func updateFrame(animated: Bool) {
        let w = model.expanded ? model.expandedW : model.compactW
        let h = model.expanded ? max(model.contentHeight, model.notchH + 90) : model.notchH
        let target = NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h)
        let cur = panel.frame
        shrinkWork?.cancel()
        if cur.width > w + 1 || cur.height > h + 1 {
            // On rétrécit la fenêtre après l'animation SwiftUI pour ne pas rogner le contenu.
            let work = DispatchWorkItem { [weak self] in self?.panel.setFrame(target, display: true) }
            shrinkWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            // Mais on recentre/élargit tout de suite si nécessaire.
            let union = cur.union(target)
            if union != cur { panel.setFrame(NSRect(x: union.minX, y: target.maxY - union.height, width: union.width, height: union.height), display: true) }
        } else {
            panel.setFrame(target, display: true)
        }
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
        if value { model.toast = nil; updateFrameForExpansion() }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { model.expanded = value }
        updateFrame(animated: true)
    }

    private func updateFrameForExpansion() {
        // Fenêtre agrandie avant l'animation du contenu.
        let w = model.expandedW, h = max(model.contentHeight, 220)
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
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

    private func notify(_ agent: Agent) {
        NSSound(named: agent.state == .waiting ? "Funk" : "Glass")?.play()
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        model.flashPane = agent.id
        // L'île est sur l'écran de la notch : si l'utilisateur travaille ailleurs, on le prévient là où il regarde.
        let loc = NSEvent.mouseLocation
        if let current = NSScreen.screens.first(where: { NSMouseInRect(loc, $0.frame, false) }), current != screen {
            banner.show(agent, on: current)
        }
        // Toast dans l'île compacte (cliquable) ; si l'île est déjà dépliée, la ligne clignote simplement.
        if !model.expanded {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { model.toast = agent }
            updateFrameForToast()
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

    private func updateFrameForToast() {
        let w = model.compactW, h = model.notchH
        panel.setFrame(NSRect(x: screen.frame.midX - w / 2, y: screen.frame.maxY - h, width: w, height: h), display: true)
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
        var area = panel.frame
        if !model.expanded {
            // Zone de survol de l'île compacte, un peu élargie vers le haut/les côtés.
            area = area.insetBy(dx: -6, dy: 0).union(NSRect(x: area.minX - 6, y: area.minY, width: area.width + 12, height: area.height + 6))
        }
        let inside = area.contains(loc)
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
        if ch == "j" { jumpToNextAttention(); return true }
        let visible = store.visibleAgents
        if let n = Int(ch), n >= 1, n <= visible.count { jump(to: visible[n - 1]); return true }
        return false
    }
}
