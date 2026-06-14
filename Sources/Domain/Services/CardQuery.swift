import Foundation

/// Pure, side-effect-free card search over a loaded `BoardState`. Extracted as a `static` function
/// (not a Service method) so the matching rule is unit-testable in isolation, without a Repository
/// or `mutate` — `BoardManagementService.matchingCardIDs` is a thin in-memory wrapper that loads the
/// active board and applies this (ticket 59B10FBA).
///
/// The match is **card-scoped, OR-combined, case-insensitive substring** across four fields: the
/// card's title, its Markdown body, the text of any sticky on its canvas, and the card's own UUID
/// string. A blank query (empty or whitespace-only) means "no filter" — every card matches — so the
/// caller surfaces all cards rather than an empty board.
enum CardQuery {
    /// The set of card ids in `state` matching `query` under the rule above. A blank query returns
    /// **every** card id (the no-filter sentinel the caller maps to "show all").
    static func matchingCardIDs(in state: BoardState, query: String) -> Set<UUID> {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Set(state.cards.map(\.id))
        }
        // Sticky text is grouped by card once so a card with many stickies costs one dictionary
        // lookup per card rather than a full sticky scan per card (O(stickies + cards) overall).
        let stickyTextByCard = Dictionary(grouping: state.stickies, by: \.cardID)
            .mapValues { $0.map(\.content) }

        let matched = state.cards.filter { card in
            if card.title.localizedCaseInsensitiveContains(trimmed) { return true }
            if card.markdownContent.localizedCaseInsensitiveContains(trimmed) { return true }
            // UUIDs are stored upper-cased; `localizedCaseInsensitiveContains` makes the input
            // case-irrelevant, so a lower-case paste of a card id still matches.
            if card.id.uuidString.localizedCaseInsensitiveContains(trimmed) { return true }
            if let texts = stickyTextByCard[card.id],
               texts.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) }) {
                return true
            }
            return false
        }
        return Set(matched.map(\.id))
    }
}
