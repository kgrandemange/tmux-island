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
        case .working: return "en cours"
        case .waiting: return "en attente"
        case .done: return "terminé"
        case .background: return "en arrière-plan"
        case .idle: return "inactif"
        }
    }
}
