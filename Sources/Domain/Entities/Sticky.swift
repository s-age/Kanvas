import Foundation

struct Sticky: Sendable, Identifiable, Equatable {
    let id: UUID
    var cardID: Card.ID
    var linkedCardID: Card.ID?
    var content: String
    var position: CanvasPosition
    var size: StickySize
    var style: StickyTextStyle
    /// Per-sticky background **fill** colour ("RRGGBB"), or `nil` to inherit the board's free/task
    /// default fill. Distinct from `style.colorHex` (the text colour). Set from the chosen palette
    /// preset's colour at creation; the canvas tint resolver (`CanvasNSView.tintColor(for:)`)
    /// prefers it over the board default when present.
    var fillColorHex: String?
    /// Stacking order within a card's canvas — higher draws in front.
    var sortIndex: Int
    /// IDs of the shared `StickyLabel`s tagged on this sticky (see `BoardState.labels`).
    var labelIDs: [UUID]

    var isTask: Bool { linkedCardID != nil }

    init(
        id: UUID = UUID(),
        cardID: Card.ID,
        linkedCardID: Card.ID? = nil,
        content: String,
        position: CanvasPosition,
        size: StickySize = .default,
        style: StickyTextStyle = .default,
        fillColorHex: String? = nil,
        sortIndex: Int,
        labelIDs: [UUID] = []
    ) {
        self.id = id
        self.cardID = cardID
        self.linkedCardID = linkedCardID
        self.content = content
        self.position = position
        self.size = size
        self.style = style
        self.fillColorHex = fillColorHex
        self.sortIndex = sortIndex
        self.labelIDs = labelIDs
    }
}
