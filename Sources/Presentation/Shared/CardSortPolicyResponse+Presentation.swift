import Foundation

extension CardSortPolicyResponse {
    /// Human-readable label for the Board settings sort-policy picker.
    var displayName: String {
        switch self {
        case .manual: return "Manual (drag order)"
        case .titleAscending: return "Title (A→Z)"
        case .createdNewest: return "Created (newest first)"
        case .createdOldest: return "Created (oldest first)"
        }
    }
}
