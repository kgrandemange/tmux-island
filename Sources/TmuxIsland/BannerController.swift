import AppKit
import SwiftUI

/// Small banner shown on the screen the user is working on when the island (on the notch) is on another screen.
@MainActor
final class BannerController {
    private var panel: NSPanel?
    private var dismissWork: DispatchWorkItem?
    var onJump: ((Agent) -> Void)?

    func show(_ agent: Agent, on screen: NSScreen) {
        dismissWork?.cancel()
        panel?.orderOut(nil)

        let size = NSSize(width: 380, height: 52)
        let view = BannerView(agent: agent) { [weak self] in
            self?.hide()
            self?.onJump?(agent)
        }
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)

        let p = NSPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.contentView = host
        let vf = screen.visibleFrame
        p.setFrameOrigin(NSPoint(x: vf.midX - size.width / 2, y: vf.maxY - size.height - 10))
        p.alphaValue = 0
        p.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 1
        }
        panel = p

        let work = DispatchWorkItem { [weak self] in self?.hide() }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    func hide() {
        dismissWork?.cancel()
        guard let p = panel else { return }
        panel = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.25
            p.animator().alphaValue = 0
        }, completionHandler: { p.orderOut(nil) })
    }
}

struct BannerView: View {
    let agent: Agent
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            StateDot(state: agent.state)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(agent.displayName).font(.system(size: 12, weight: .semibold))
                    Text(agent.pane.project).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(agent.state == .waiting ? L10n.tr("banner.waiting") : L10n.tr("banner.done"))
                    .font(.system(size: 11)).foregroundStyle(agent.state.color)
            }
            Spacer(minLength: 0)
            Text(L10n.tr("banner.go")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(width: 380, height: 52)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .background(Capsule().fill(Color.black))
        .overlay(Capsule().stroke(agent.state.color.opacity(0.5), lineWidth: 1))
        .contentShape(Capsule())
        .onTapGesture(perform: onTap)
    }
}
