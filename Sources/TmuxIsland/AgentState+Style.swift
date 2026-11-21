import SwiftUI

extension AgentState {
    var color: Color {
        switch self {
        case .working: return Color(red: 1.0, green: 0.62, blue: 0.04)
        case .waiting: return Color(red: 1.0, green: 0.27, blue: 0.23)
        case .done: return Color(red: 0.19, green: 0.82, blue: 0.35)
        case .background: return Color(red: 0.40, green: 0.65, blue: 1.0)
        case .idle: return Color.white.opacity(0.28)
        }
    }

    var label: String {
        switch self {
        case .working: return L10n.tr("state.working")
        case .waiting: return L10n.tr("state.waiting")
        case .done: return L10n.tr("state.done")
        case .background: return L10n.tr("state.background")
        case .idle: return L10n.tr("state.idle")
        }
    }
}
