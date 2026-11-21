import SwiftUI

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
                        Text(agent.state == .background ? agent.state.label + (agent.detail.map { " · \($0)" } ?? "") : agent.state.label)
                            .font(.system(size: 10)).foregroundStyle(agent.state.color).lineLimit(1)
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
                if agent.state == .waiting && agent.options.isEmpty {
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
            if agent.state == .waiting && !agent.options.isEmpty {
                HStack(spacing: 6) {
                    ForEach(agent.options.prefix(4)) { o in
                        ActionButton(title: "\(o.number) · \(o.shortLabel)", prominent: o.selected) {
                            FocusService.choose(o, on: agent.pane)
                        }
                        .help(o.label)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.top, 8)
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
