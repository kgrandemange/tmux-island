import AppKit
import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    /// Natural height of the expanded content (measured): used to animate the island's height from the notch to here.
    /// Initial value is an estimate, corrected on the first measurement.
    @Published var contentHeight: CGFloat = 300
    /// Off-screen renders (ImageRenderer): the height follows the content without animation.
    var naturalHeight = false
    @Published var flashPane: String?
    /// Agent that just finished: the compact island widens for a few seconds to announce it.
    @Published var toast: Agent?
    @Published var historyOpen = false
    /// Pane whose screen preview is expanded (row hover).
    @Published var hoveredPane: String?
    /// Areas of the agent rows (island coordinates, origin at top left), published by the view.
    var rowFrames: [String: CGRect] = [:]
    private var hoverWork: DispatchWorkItem?
    private var requestedRow: String?

    /// Hover comes from the real cursor position (not `onHover`, which emits false
    /// "exited / entered" events when the window resizes under the cursor and makes the preview loop).
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
    /// Focus mode: no sound, toast or banner — only the status dots remain.
    @Published var focusMode = UserDefaults.standard.bool(forKey: "focusMode")
    var onToggleFocus: (() -> Void)?
    var notchW: CGFloat = 190
    var notchH: CGFloat = 32
    let wing: CGFloat = 74
    let expandedW: CGFloat = 600
    var compactW: CGFloat { notchW + 2 * (toast == nil ? wing : toastWing) }
    let toastWing: CGFloat = 150
    var requestKey: (() -> Void)?
    var onJump: ((Agent) -> Void)?
    var onJumpPane: ((Pane) -> Void)?
    var onTapCompact: (() -> Void)?
}
