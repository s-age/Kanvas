/// A card's status, **derived from the column it sits in** — never stored on the card. The full
/// case set is exactly what `BoardState.status(forColumn:)` can return: completion column → `.done`,
/// leftmost column → `.todo`, every column in between → `.inProgress`. There is intentionally no
/// "blocked" case: no column maps to it, so it would be permanently unreachable vocabulary.
enum CardStatus: String, Sendable, Equatable {
    case todo
    case inProgress
    case done
}
