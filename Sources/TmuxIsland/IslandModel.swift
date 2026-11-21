import AppKit
import SwiftUI

@MainActor
final class IslandModel: ObservableObject {
    @Published var expanded = false
    /// Hauteur naturelle du contenu déplié (mesurée) : sert à animer la hauteur de l'île de la notch jusqu'ici.
    /// Valeur de départ = estimation, corrigée dès la première mesure.
    @Published var contentHeight: CGFloat = 300
    /// Captures hors écran (ImageRenderer) : la hauteur suit le contenu sans être animée.
    var naturalHeight = false
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
    let wing: CGFloat = 74
    let expandedW: CGFloat = 600
    var compactW: CGFloat { notchW + 2 * (toast == nil ? wing : toastWing) }
    let toastWing: CGFloat = 150
    var requestKey: (() -> Void)?
    var onJump: ((Agent) -> Void)?
    var onJumpPane: ((Pane) -> Void)?
    var onTapCompact: (() -> Void)?
}
