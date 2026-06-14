import SwiftUI

extension CardStatusResponse {
    var displayColor: Color {
        switch self {
        case .todo: .blue
        case .inProgress: .orange
        case .done: .green
        }
    }
}
