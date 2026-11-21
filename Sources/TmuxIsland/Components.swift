import SwiftUI

/// Context fill gauge: grey at rest, orange above 60 %, red above 85 %.
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
        .help(L10n.tr("context.help", label, info.window / 1000, Int(info.fraction * 100)))
        .padding(.trailing, 6)
    }
}

/// Accordion: the height animates from 0 to the content's natural height, and the content is clipped during the animation
/// (no empty gap, no text overflowing onto neighboring sections).
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

/// tmux logo: four "panes", one of them active (brighter). Replaces the generic terminal icon.
struct PaneGlyph: View {
    var strength: Double = 1

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) { pane(active: true); pane(active: false) }
            HStack(spacing: 2) { pane(active: false); pane(active: false) }
        }
        .frame(width: 14, height: 11)
        .accessibilityLabel("tmux")
    }

    private func pane(active: Bool) -> some View {
        RoundedRectangle(cornerRadius: 1.5).fill(Color.white.opacity((active ? 0.85 : 0.32) * strength))
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
            } else if state == .background {
                RingDot(color: state.color, size: 9)
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

/// Dot of the compact wing: breathes while the agent works, beats harder when action is needed.
/// Hollow ring that breathes slowly: "shells are running in the background", without the urgency of a solid dot.
struct RingDot: View {
    let color: Color
    var size: CGFloat = 7
    @State private var on = false
    var body: some View {
        Circle().stroke(color, lineWidth: max(1.5, size / 5)).frame(width: size, height: size)
            .opacity(on ? 1 : 0.45)
            .onAppear { withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { on = true } }
    }
}

struct AgentDot: View {
    let state: AgentState
    @State private var on = false
    var body: some View {
        if state == .background {
            RingDot(color: state.color)
        } else {
            solid
        }
    }

    private var solid: some View {
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
    var prominent = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 10, weight: .semibold))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(prominent ? AgentState.done.color.opacity(0.4) : Color.white.opacity(0.16)))
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
