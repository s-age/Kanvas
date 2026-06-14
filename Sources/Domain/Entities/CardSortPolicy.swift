import Foundation

enum CardSortPolicy: String, Sendable, Equatable {
    case manual
    case titleAscending
    case createdNewest
    case createdOldest

    /// Returns `cards` in the display order this policy dictates. `manual` preserves the
    /// user's drag order (`sortIndex`); every other policy derives order from card fields,
    /// always falling back to `sortIndex` as a deterministic tiebreaker (Swift's sort is not
    /// guaranteed stable, and legacy cards share a `.distantPast` creation timestamp).
    /// Pure transform — no mutation of `sortIndex`, so drag order survives a policy switch.
    func ordered(_ cards: [Card]) -> [Card] {
        switch self {
        case .manual:
            return cards.sorted { $0.sortIndex < $1.sortIndex }
        case .titleAscending:
            return cards.sorted { lhs, rhs in
                let comparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
                if comparison == .orderedSame { return lhs.sortIndex < rhs.sortIndex }
                return comparison == .orderedAscending
            }
        case .createdNewest:
            return cards.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt > rhs.createdAt
            }
        case .createdOldest:
            return cards.sorted { lhs, rhs in
                if lhs.createdAt == rhs.createdAt { return lhs.sortIndex < rhs.sortIndex }
                return lhs.createdAt < rhs.createdAt
            }
        }
    }
}
