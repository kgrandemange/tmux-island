import SwiftUI

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

/// Appearance of the expanded content: fade + slight blur + a few pixels of slide.
private struct BlurReveal: ViewModifier {
    var amount: Double   // 1 = hidden, 0 = visible
    func body(content: Content) -> some View {
        content.opacity(1 - amount).blur(radius: 6 * amount).offset(y: -8 * amount)
    }
}

extension AnyTransition {
    static func blurReveal(in inAnimation: Animation, out outAnimation: Animation) -> AnyTransition {
        .asymmetric(
            insertion: AnyTransition.modifier(active: BlurReveal(amount: 1), identity: BlurReveal(amount: 0)).animation(inAnimation),
            removal: AnyTransition.modifier(active: BlurReveal(amount: 1), identity: BlurReveal(amount: 0)).animation(outAnimation))
    }
}

struct IslandView: View {
    @ObservedObject var store: AgentStore
    @ObservedObject var model: IslandModel
    @ObservedObject private var shortcuts = ShortcutStore.shared

    /// Height of the shape: from the notch to the content's height, animated with the width ("morph").
    private var islandHeight: CGFloat? {
        if model.naturalHeight { return nil }
        return model.expanded ? max(model.contentHeight, model.notchH + 60) : model.notchH
    }

    var body: some View {
        let w = model.expanded ? model.expandedW : model.compactW
        ZStack(alignment: .top) {
            ZStack(alignment: .top) {
                if model.expanded {
                    expanded
                        .background(GeometryReader { g in Color.clear.preference(key: HeightKey.self, value: g.size.height) })
                        .transition(.blurReveal(in: .easeOut(duration: 0.30).delay(0.14), out: .easeIn(duration: 0.12)))
                } else {
                    compact
                        .transition(.asymmetric(insertion: AnyTransition.opacity.animation(.easeOut(duration: 0.15).delay(0.12)),
                                                removal: AnyTransition.opacity.animation(.easeIn(duration: 0.10))))
                }
            }
            .foregroundStyle(.white)
            .environment(\.colorScheme, .dark)
            .frame(width: w, height: islandHeight, alignment: .top)
            .background(NotchShape(topR: model.expanded ? 18 : 6, botR: model.expanded ? 26 : 12).fill(Color.black))
            .clipShape(NotchShape(topR: model.expanded ? 18 : 6, botR: model.expanded ? 26 : 12))
            .animation(.easeOut(duration: 0.22), value: model.contentHeight)
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
            Text(t.state == .waiting ? L10n.tr("toast.waiting") : L10n.tr("toast.done"))
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
            // Left wing: tmux presence (always visible) + number of sessions
            HStack(spacing: 5) {
                if model.focusMode {
                    Image(systemName: "moon.fill").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(red: 0.68, green: 0.55, blue: 1.0))
                } else {
                    PaneGlyph(strength: store.tmuxRunning ? 0.75 : 0.3)
                }
                if store.tmuxRunning {
                    Text("\(store.sessions.count)").font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            .frame(width: model.wing, alignment: .trailing)
            .padding(.trailing, 6)
            Spacer(minLength: 0).frame(width: model.notchW - 12)
            // Right wing: one dot per agent, sorted by urgency (red, green, orange, grey)
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

    // MARK: Expanded

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
                PaneGlyph(strength: 0.8)
                Text("tmux").font(.system(size: 12, weight: .semibold))
                summaryPills
            }
            .padding(.leading, 34)
            Spacer(minLength: model.notchW)
            HStack(spacing: 10) {
                Button { model.onToggleFocus?() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.focusMode ? "moon.fill" : "moon")
                        Text(L10n.tr("island.focus")).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(model.focusMode ? Color(red: 0.68, green: 0.55, blue: 1.0) : Color.white.opacity(0.5))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(model.focusMode ? Color(red: 0.68, green: 0.55, blue: 1.0).opacity(0.2) : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Text(shortcuts.shortcut(.toggle).label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
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
            if store.backgroundCount > 0 { Pill(text: "\(store.backgroundCount)", color: AgentState.background.color) }
        }
    }

    private var agentsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.visibleAgents.isEmpty {
                Text(!store.tmuxRunning ? L10n.tr("empty.tmuxDown")
                     : store.agents.isEmpty ? L10n.tr("empty.noAgent")
                     : L10n.plural("empty.idle", store.idleCount))
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
                    Text(L10n.tr("section.recent")).font(.system(size: 9, weight: .semibold)).tracking(1)
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
            Text(L10n.tr("section.sessions")).font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.tertiary)
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
            Hint(key: "1-9", text: L10n.tr("hint.goto"))
            Hint(key: "J", text: L10n.tr("hint.next"))
            Hint(key: "F", text: L10n.tr("hint.focus"))
            Hint(key: "Esc", text: L10n.tr("hint.close"))
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Composants
