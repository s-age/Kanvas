import Foundation

extension NewCardPositionResponse {
    /// Human-readable label for the Board settings new-card-position picker.
    var displayName: String {
        switch self {
        case .top: return "Top of column"
        case .bottom: return "Bottom of column"
        }
    }
}
