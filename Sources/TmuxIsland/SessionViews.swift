import SwiftUI

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

/// "Flow" layout: items wrap to the next line instead of being truncated.
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
