import SwiftUI

extension AgentState {
    var color: Color {
        switch self {
        case .working: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .waiting: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .done: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .idle: return Color.white.opacity(0.28)
        }
    }

    var label: String {
        switch self {
        case .working: return "en cours"
        case .waiting: return "en attente"
        case .done: return "terminé"
        case .idle: return "inactif"
        }
    }
}

struct NotchShape: Shape {
    var topR: CGFloat
    var botR: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topR, botR) }
        set { topR = newValue.first; botR = newValue.second }
    }

    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: topR, y: topR), control: CGPoint(x: topR, y: 0))
        p.addLine(to: CGPoint(x: topR, y: r.height - botR))
        p.addQuadCurve(to: CGPoint(x: topR + botR, y: r.height), control: CGPoint(x: topR, y: r.height))
        p.addLine(to: CGPoint(x: r.width - topR - botR, y: r.height))
        p.addQuadCurve(to: CGPoint(x: r.width - topR, y: r.height - botR), control: CGPoint(x: r.width - topR, y: r.height))
        p.addLine(to: CGPoint(x: r.width - topR, y: topR))
        p.addQuadCurve(to: CGPoint(x: r.width, y: 0), control: CGPoint(x: r.width - topR, y: 0))
        p.closeSubpath()
        return p
    }
}

struct RowFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

private struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct IslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var model: IslandModel

    var body: some View {
        let w = model.expanded ? model.expandedW : model.compactW
        ZStack(alignment: .top) {
            Group {
                if model.expanded { expanded } else { compact }
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .frame(width: w)
            .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
            .background(NotchShape(topR: model.expanded ? 18 : 6, botR: model.expanded ? 26 : 12).fill(Color.black))
            .clipShape(NotchShape(topR: model.expanded ? 18 : 6, botR: model.expanded ? 26 : 12))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .coordinateSpace(name: "island")
        .onPreferenceChange(HeightKey.self) { h in if model.expanded { model.contentHeight = h } }
        .onPreferenceChange(RowFramesKey.self) { model.rowFrames = $0 }
        .preferredColorScheme(.dark)
    }

    // MARK: Compact

    @ViewBuilder private var compact: some View {
        if let t = model.toast { toastView(t) } else { idleCompact }
    }

    private func toastView(_ t: Agent) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(t.pane.project).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                AgentDot(state: t.state)
            }
            .frame(width: model.toastWing - 8, alignment: .trailing)
            .padding(.trailing, 8)
            Spacer(minLength: 0).frame(width: model.notchW - 12)
            Text(t.state == .waiting ? "attend" : "terminé")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(t.state.color)
                .frame(width: model.toastWing - 8, alignment: .leading)
                .padding(.leading, 8)
        }
        .frame(height: model.notchH)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapCompact?() }
        .transition(.opacity)
    }

    private var idleCompact: some View {
        HStack(spacing: 0) {
            // Aile gauche : présence de tmux (toujours visible) + nombre de sessions
            HStack(spacing: 5) {
                Image(systemName: model.focusMode ? "moon.fill" : "terminal").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.focusMode ? Color(red: 0.68, green: 0.55, blue: 1.0)
                                     : store.tmuxRunning ? Color.white.opacity(0.55) : Color.white.opacity(0.2))
                if store.tmuxRunning {
                    Text("\(store.sessions.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: model.wing, alignment: .trailing)
            .padding(.trailing, 6)
            Spacer(minLength: 0).frame(width: model.notchW - 12)
            // Aile droite : un point par agent, trié par urgence (rouge, vert, orange, gris)
            HStack(spacing: 4) {
                if store.agents.isEmpty {
                    Circle().stroke(Color.white.opacity(0.25), lineWidth: 1).frame(width: 7, height: 7)
                } else {
                    let maxDots = store.agents.count > 6 ? 5 : 6
                    ForEach(store.agents.prefix(maxDots)) { AgentDot(state: $0.state) }
                    if store.agents.count > 6 {
                        Text("+\(store.agents.count - 5)").font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
            .frame(width: model.wing, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: model.notchH)
        .contentShape(Rectangle())
        .onTapGesture { model.onTapCompact?() }
    }

    // MARK: Étendue

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 14) {
                agentsSection
                if !store.history.isEmpty { historySection }
                if !store.sessions.isEmpty { sessionsSection }
                footer
            }
            .padding(.horizontal, 34)
            .padding(.top, 16)
            .padding(.bottom, 18)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("tmux").font(.system(size: 12, weight: .semibold))
                summaryPills
            }
            .padding(.leading, 34)
            Spacer(minLength: model.notchW)
            HStack(spacing: 10) {
                Button { model.onToggleFocus?() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.focusMode ? "moon.fill" : "moon")
                        Text("Concentration").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.focusMode ? Color(red: 0.68, green: 0.55, blue: 1.0) : Color.white.opacity(0.5))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(model.focusMode ? Color(red: 0.68, green: 0.55, blue: 1.0).opacity(0.2) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Text("⌃⌥Space").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(.trailing, 34)
        }
        .frame(height: model.notchH)
    }

    private var summaryPills: some View {
        HStack(spacing: 6) {
            if store.workingCount > 0 { Pill(text: "\(store.workingCount)", color: AgentState.working.color) }
            if store.waitingCount > 0 { Pill(text: "\(store.waitingCount)", color: AgentState.waiting.color) }
            if store.doneCount > 0 { Pill(text: "\(store.doneCount)", color: AgentState.done.color) }
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.visibleAgents.isEmpty {
                Text(!store.tmuxRunning ? "tmux n'est pas lancé."
                     : store.agents.isEmpty ? "Aucun agent IA détecté dans tes sessions tmux."
                     : "Rien à traiter — \(store.idleCount) agent(s) inactif(s).")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 6)
            } else {
                let rows = ForEach(Array(store.visibleAgents.enumerated()), id: \.element.id) { i, agent in
                    AgentRow(agent: agent, index: i + 1, flash: model.flashPane == agent.id, model: model)
                }
                if store.visibleAgents.count > 6 {
                    ScrollView(showsIndicators: false) { VStack(spacing: 6) { rows } }.frame(height: 6 * 60)
                } else {
                    VStack(spacing: 6) { rows }
                }
            }
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.2)) { model.historyOpen.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: model.historyOpen ? "chevron.down" : "chevron.right").font(.system(size: 8, weight: .bold))
                    Text("RÉCENTS").font(.system(size: 9, weight: .semibold)).tracking(1)
                    Text("\(min(store.history.count, 10))").font(.system(size: 9, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.tertiary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if model.historyOpen {
                ForEach(store.history.prefix(10)) { e in
                    HistoryRow(entry: e, pane: store.target(for: e), model: model)
                }
            }
        }
    }

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSIONS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
            ForEach(store.sessions) { s in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(s.displayName).font(.system(size: 11, weight: .semibold)).foregroundStyle(s.attached ? .primary : .secondary)
                        .frame(width: 92, alignment: .leading).lineLimit(1)
                    FlowChips(session: s, store: store, model: model)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Hint(key: "1-9", text: "aller à l'agent")
            Hint(key: "J", text: "prochain à traiter")
            Hint(key: "F", text: "concentration")
            Hint(key: "Esc", text: "fermer")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Composants

struct AgentRow: View {
    let agent: Agent
    let index: Int
    let flash: Bool
    @ObservedObject var model: IslandModel
    @State private var hover = false
    @State private var replying = false
    @State private var reply = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                StateDot(state: agent.state)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agent.displayName).font(.system(size: 12, weight: .semibold))
                        Text("\(agent.pane.session) › \(agent.pane.windowName)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
                        if let u = agent.usage { ContextMeter(info: u) }
                        Text(agent.state.label).font(.system(size: 10)).foregroundStyle(agent.state.color)
                        if agent.state != .idle {
                            Text(agent.since, style: .timer).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary).frame(width: 44, alignment: .trailing)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(agent.pane.project).font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary)
                        Text(agent.preview).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                if agent.state == .waiting {
                    ActionButton(title: "↵ Valider") { FocusService.sendEnter(to: agent.pane) }
                }
                if agent.state.needsAttention {
                    ActionButton(title: "Répondre") {
                        replying.toggle()
                        if replying { model.requestKey?(); focused = true }
                    }
                }
                if index <= 9 { KeyCap(text: "\(index)") }
            }
            if !agent.screen.isEmpty {
                Reveal(open: model.hoveredPane == agent.id) {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(agent.screen.enumerated()), id: \.offset) { _, line in
                            Text(line).font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.72)).lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10).padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.06)))
                }
            }
            if replying {
                TextField("Réponse rapide (↵ pour envoyer)", text: $reply)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
                    .padding(.top, 6)
                    .focused($focused)
                    .onSubmit {
                        guard !reply.isEmpty else { return }
                        FocusService.reply(to: agent.pane, text: reply)
                        reply = ""
                        replying = false
                    }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white.opacity(hover ? 0.13 : 0.07))
                .overlay(RoundedRectangle(cornerRadius: 12)
                    .stroke(flash ? agent.state.color : .clear, lineWidth: 1.5))
        )
        .contentShape(Rectangle())
        .background(GeometryReader { g in
            Color.clear.preference(key: RowFramesKey.self, value: [agent.id: g.frame(in: .named("island"))])
        })
        .onHover { hover = $0 }
        .onTapGesture { model.onJump?(agent) }
    }
}

/// Jauge de remplissage du contexte : grise au repos, orange > 60 %, rouge > 85 %.
struct ContextMeter: View {
    let info: ClaudeUsage.Info

    private var color: Color {
        info.fraction > 0.85 ? AgentState.waiting.color : info.fraction > 0.6 ? AgentState.working.color : Color.white.opacity(0.5)
    }

    private var label: String {
        info.tokens >= 1_000_000 ? String(format: "%.1fM", Double(info.tokens) / 1e6) : "\(info.tokens / 1000)k"
    }

    var body: some View {
        HStack(spacing: 4) {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12)).frame(width: 30, height: 4)
                Capsule().fill(color).frame(width: max(3, 30 * info.fraction), height: 4)
            }
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(color)
        }
        .help("Contexte : \(label) / \(info.window / 1000)k (\(Int(info.fraction * 100)) %)")
        .padding(.trailing, 6)
    }
}

struct HistoryRow: View {
    let entry: HistoryEntry
    let pane: Pane?
    @ObservedObject var model: IslandModel
    @State private var hover = false

    var body: some View {
        let color = entry.waiting ? AgentState.waiting.color : AgentState.done.color
        HStack(spacing: 8) {
            Image(systemName: entry.waiting ? "exclamationmark" : "checkmark")
                .font(.system(size: 8, weight: .bold)).foregroundStyle(color)
                .frame(width: 16, height: 16).background(Circle().fill(color.opacity(0.2)))
            Text("\(entry.agentName) · \(entry.project)").font(.system(size: 11, weight: .medium)).lineLimit(1)
            Text("\(entry.session) › \(entry.windowName)").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Spacer(minLength: 4)
            Text(entry.date, style: .relative).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
        }
        .padding(.horizontal, 10).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(hover && pane != nil ? 0.1 : 0.04)))
        .opacity(pane == nil ? 0.4 : 1)
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { if let pane { model.onJumpPane?(pane) } }
    }
}

/// Accordéon : la hauteur s'anime de 0 à la hauteur naturelle du contenu, qui est rogné pendant l'animation
/// (pas de trou vide, pas de texte qui déborde sur les sections voisines).
struct Reveal<Content: View>: View {
    let open: Bool
    @ViewBuilder let content: () -> Content
    @State private var natural: CGFloat = 0
    private let gap: CGFloat = 6

    var body: some View {
        content()
            .fixedSize(horizontal: false, vertical: true)
            .background(GeometryReader { g in Color.clear.preference(key: RevealHeightKey.self, value: g.size.height) })
            .onPreferenceChange(RevealHeightKey.self) { natural = $0 }
            .frame(height: open ? natural : 0, alignment: .top)
            .clipped()
            .opacity(open ? 1 : 0)
            .padding(.top, open ? gap : 0)
            .allowsHitTesting(false)
    }
}

private struct RevealHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// Mise en page « flux » : les éléments passent à la ligne au lieu d'être tronqués.
struct WrapLayout: Layout {
    var spacing: CGFloat = 5

    private func arrange(_ width: CGFloat, _ subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, usedW: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0 && x + sz.width > width { y += rowH + spacing; x = 0; rowH = 0 }
            frames.append(CGRect(x: x, y: y, width: sz.width, height: sz.height))
            x += sz.width + spacing
            usedW = max(usedW, x - spacing)
            rowH = max(rowH, sz.height)
        }
        return (frames, CGSize(width: usedW, height: y + rowH))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(proposal.width ?? 10_000, subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (frames, _) = arrange(bounds.width, subviews)
        for (s, f) in zip(subviews, frames) {
            s.place(at: CGPoint(x: bounds.minX + f.minX, y: bounds.minY + f.minY), proposal: ProposedViewSize(f.size))
        }
    }
}

struct FlowChips: View {
    let session: TmuxSession
    @ObservedObject var store: AgentStore
    @ObservedObject var model: IslandModel

    var body: some View {
        WrapLayout(spacing: 5) {
            ForEach(session.windows) { w in
                let st = store.state(ofWindow: w)
                Button {
                    model.onJumpPane?(w.activePane)
                } label: {
                    HStack(spacing: 4) {
                        if let st { Circle().fill(st.color).frame(width: 6, height: 6) }
                        Text("\(w.index)").font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                        Text(w.name).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                            .frame(maxWidth: 230, alignment: .leading)
                    }
                    .fixedSize()
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(w.active && session.attached ? 0.18 : 0.08)))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StateDot: View {
    let state: AgentState
    var body: some View {
        ZStack {
            Circle().fill(state.color.opacity(0.22)).frame(width: 22, height: 22)
            if state == .working {
                PulsingDot(color: state.color)
            } else if state == .done {
                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(state.color)
            } else if state == .waiting {
                Image(systemName: "exclamationmark").font(.system(size: 11, weight: .bold)).foregroundStyle(state.color)
            } else {
                Circle().fill(state.color).frame(width: 7, height: 7)
            }
        }
    }
}

struct PulsingDot: View {
    let color: Color
    @State private var on = false
    var body: some View {
        Circle().fill(color).frame(width: 8, height: 8)
            .scaleEffect(on ? 1.0 : 0.6).opacity(on ? 1 : 0.55)
            .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true } }
    }
}

/// Point de l'aile compacte : respire quand l'agent travaille, bat plus fort quand il faut agir.
struct AgentDot: View {
    let state: AgentState
    @State private var on = false
    var body: some View {
        Circle().fill(state.color).frame(width: 7, height: 7)
            .scaleEffect(animated ? (on ? 1.25 : 0.75) : 1)
            .opacity(state == .working ? (on ? 1 : 0.5) : 1)
            .shadow(color: state.needsAttention ? state.color.opacity(0.8) : .clear, radius: 3)
            .onAppear {
                guard animated else { return }
                withAnimation(.easeInOut(duration: state == .working ? 0.9 : 0.6).repeatForever(autoreverses: true)) { on = true }
            }
    }
    private var animated: Bool { state != .idle }
}

struct Badge: View {
    let count: Int
    let color: Color
    var pulse = false
    @State private var on = false
    var body: some View {
        Text("\(count)")
            .font(.system(size: 11, weight: .bold, design: .rounded)).foregroundStyle(.black)
            .frame(minWidth: 18).padding(.vertical, 1)
            .background(Capsule().fill(color))
            .scaleEffect(pulse && on ? 1.12 : 1)
            .onAppear {
                guard pulse else { return }
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct Pill: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.system(size: 10, weight: .semibold, design: .rounded)).foregroundStyle(.secondary)
        }
    }
}

struct ActionButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(Color.white.opacity(0.16)))
        }
        .buttonStyle(.plain)
    }
}

struct KeyCap: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
            .padding(.horizontal, 4)
            .frame(minWidth: 18, minHeight: 18)
            .fixedSize()
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(0.2)))
    }
}

struct Hint: View {
    let key: String
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            KeyCap(text: key).fixedSize()
            Text(text).font(.system(size: 10)).foregroundStyle(.tertiary)
        }
    }
}
