import Foundation

struct BoardResponse: Sendable, Equatable {
    let board: BoardSummary
    let columns: [ColumnResponse]
    /// App-wide registry of all sticky labels — the source for the label-management panel.
    let labels: [StickyLabelResponse]
    let settings: BoardSettingsResponse
}

struct BoardSummary: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
}

/// The board picker's read-model: every board plus which one is active. Named distinctly from
/// `BoardResponse` (one board's full content) — the two are easy to confuse otherwise. Kept
/// separate so the ~40 board-mutating use cases never thread the board list through their mappers.
struct BoardListResponse: Sendable, Equatable {
    let boards: [BoardSummary]
    let activeBoardID: UUID?
}

/// `AddCardUseCaseImpl`'s result: the refreshed board plus the created card's identity, so callers
/// (rename-mode focus in the app, the MCP gateway's reply) address the new card directly instead
/// of diffing pre/post card sets — a diff can blame a concurrently added card under the shared
/// multi-process store.
struct AddCardResponse: Sendable, Equatable {
    let newCardID: UUID
    let board: BoardResponse
}

struct ColumnResponse: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let sortIndex: Int
    let isCompletionColumn: Bool
    /// Per-column header background (hex); `nil` ⇒ no fill.
    let headerColorHex: String?
    /// Per-column header text (hex); `nil` ⇒ board text colour.
    let headerTextColorHex: String?
    /// Per-column body (card-stack area) background (hex); `nil` ⇒ default tint.
    let bodyColorHex: String?
    /// Per-column header border (hex); `nil` ⇒ no border.
    let headerBorderColorHex: String?
    /// Per-column body border (hex); `nil` ⇒ no border.
    let bodyBorderColorHex: String?
    /// Per-column status-indicator dot (hex); `nil` ⇒ neutral default (`.boardDefaultStatusDot`).
    let indicatorColorHex: String?
    let cards: [CardSummary]
}

struct CardSummary: Sendable, Equatable, Identifiable {
    let id: UUID
    let title: String
    let status: CardStatusResponse
    let hasSchedule: Bool
    let labelCount: Int
}

/// A card's status exposed to Presentation. Mirrors the domain `CardStatus` raw values;
/// Presentation switches on this (status dot / chip colour) instead of importing the domain enum
/// (the layer boundary forbids it). The case set is closed — see `CardStatus` for why there is no
/// "blocked" case.
///
/// Read-only on purpose: there is `init(_:)` (Domain→Response) but no `toDomain` — status is
/// derived from the card's column (`BoardState.status(forColumn:)`), never edited or written back,
/// so the reverse direction would be unreachable vocabulary.
enum CardStatusResponse: String, Sendable, Equatable {
    case todo
    case inProgress
    case done

    init(_ status: CardStatus) {
        switch status {
        case .todo: self = .todo
        case .inProgress: self = .inProgress
        case .done: self = .done
        }
    }
}
