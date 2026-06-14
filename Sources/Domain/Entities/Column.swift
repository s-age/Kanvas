import Foundation

struct Column: Sendable, Identifiable, Equatable {
    let id: UUID
    var boardID: Board.ID
    var title: String
    var sortIndex: Int
    /// When true, a card moved into this column gets its `completedAt` stamped.
    /// At most one column per board is the completion column (enforced by `ColumnService`).
    var isCompletionColumn: Bool
    /// Per-column header **background** colour (hex). `nil` falls back to the board-wide default.
    var headerColorHex: String?
    /// Per-column header **text** colour (hex). `nil` falls back to the board text colour.
    var headerTextColorHex: String?
    /// Per-column body **background** colour (hex) — the column's card-stack area behind the cards.
    /// `nil` falls back to the default tint.
    var bodyColorHex: String?
    /// Per-column header **border** colour (hex). `nil` ⇒ no border.
    var headerBorderColorHex: String?
    /// Per-column body **border** colour (hex). `nil` ⇒ no border.
    var bodyBorderColorHex: String?
    /// Per-column **status-indicator dot** colour (hex) — the small dot at the head of each card in
    /// this column. `nil` ⇒ a fixed neutral default (Presentation `.boardDefaultStatusDot`); the dot
    /// no longer follows the card's status colour.
    var indicatorColorHex: String?

    init(
        id: UUID = UUID(),
        boardID: Board.ID,
        title: String,
        sortIndex: Int,
        isCompletionColumn: Bool = false,
        headerColorHex: String? = nil,
        headerTextColorHex: String? = nil,
        bodyColorHex: String? = nil,
        headerBorderColorHex: String? = nil,
        bodyBorderColorHex: String? = nil,
        indicatorColorHex: String? = nil
    ) {
        self.id = id
        self.boardID = boardID
        self.title = title
        self.sortIndex = sortIndex
        self.isCompletionColumn = isCompletionColumn
        self.headerColorHex = headerColorHex
        self.headerTextColorHex = headerTextColorHex
        self.bodyColorHex = bodyColorHex
        self.headerBorderColorHex = headerBorderColorHex
        self.bodyBorderColorHex = bodyBorderColorHex
        self.indicatorColorHex = indicatorColorHex
    }
}
