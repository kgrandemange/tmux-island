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
        .onPreferenceChange(HeightKey.self) { h in if model.expanded { model.contentHeight = h } }
        .preferredColorScheme(.dark)
    }

    // MARK: Compact

    private var compact: some View {
        HStack(spacing: 0) {
            // Aile gauche : présence (toujours visible) + agents en cours
            HStack(spacing: 5) {
                Image(systemName: "terminal").font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(store.tmuxRunning ? Color.white.opacity(0.55) : Color.white.opacity(0.2))
                if store.workingCount > 0 {
                    PulsingDot(color: AgentState.working.color)
                    Text("\(store.workingCount)").font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AgentState.working.color)
                } else if store.tmuxRunning {
                    Text("\(store.sessions.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: model.wing, alignment: .trailing)
            .padding(.trailing, 6)
            Spacer(minLength: 0).frame(width: model.notchW - 12)
            // Aile droite : à traiter, sinon nombre d'agents inactifs
            HStack(spacing: 6) {
                if store.waitingCount > 0 { Badge(count: store.waitingCount, color: AgentState.waiting.color, pulse: true) }
                if store.doneCount > 0 { Badge(count: store.doneCount, color: AgentState.done.color, pulse: true) }
                if store.waitingCount == 0 && store.doneCount == 0 {
                    Circle().fill(AgentState.idle.color).frame(width: 6, height: 6)
                    Text("\(store.agents.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: model.wing, alignment: .leading)
            .padding(.leading, 6)
        }
        .frame(height: model.notchH)
    }

    // MARK: Étendue

    private var expanded: some View {
        VStack(spacing: 0) {
            header
            VStack(alignment: .leading, spacing: 12) {
                agentsSection
                if !store.sessions.isEmpty { sessionsSection }
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 10)
            .padding(.bottom, 20)
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(.secondary)
                Text("tmux").font(.system(size: 12, weight: .semibold))
                summaryPills
            }
            .padding(.leading, 28)
            Spacer(minLength: model.notchW)
            Text("⌃⌥Space").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                .padding(.trailing, 28)
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

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SESSIONS").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
            ForEach(store.sessions) { s in
                HStack(alignment: .center, spacing: 8) {
                    Text(s.name).font(.system(size: 11, weight: .semibold)).foregroundStyle(s.attached ? .primary : .secondary)
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
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                StateDot(state: agent.state)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(agent.displayName).font(.system(size: 12, weight: .semibold))
                        Text("\(agent.pane.session) › \(agent.pane.windowName)")
                            .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 4)
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
            if replying {
                TextField("Réponse rapide (↵ pour envoyer)", text: $reply)
                    .textFieldStyle(.plain).font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)))
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
        .onHover { hover = $0 }
        .onTapGesture { model.onJump?(agent) }
    }
}

struct FlowChips: View {
    let session: TmuxSession
    @ObservedObject var store: AgentStore
    @ObservedObject var model: IslandModel

    var body: some View {
        HStack(spacing: 5) {
            ForEach(session.windows.prefix(8)) { w in
                let st = store.state(ofWindow: w)
                Button {
                    model.onJumpPane?(w.activePane)
                } label: {
                    HStack(spacing: 4) {
                        if let st { Circle().fill(st.color).frame(width: 6, height: 6) }
                        Text("\(w.index) \(w.name)").font(.system(size: 10)).lineLimit(1)
                    }
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.white.opacity(w.active && session.attached ? 0.18 : 0.08)))
                }
                .buttonStyle(.plain)
            }
            if session.windows.count > 8 {
                Text("+\(session.windows.count - 8)").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
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
