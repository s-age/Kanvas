import Foundation

/// A free-text object on a card's canvas — plain text with **no background and no border**, freely
/// positioned. The fifth canvas object kind, a sibling of `Sticky` / `CanvasShape` / `CanvasImage` /
/// `Connector`. Distinct from a free *sticky* (which is text on a coloured background): a `CanvasText`
/// is just the glyphs. It carries none of the sticky's satellite features — no `linkedCardID`
/// (no promote/demote), no `labelIDs`, and connectors cannot attach to it (connectors stay
/// sticky-only). Text wraps to `size.width`; anything taller than `size.height` is clipped (hidden)
/// at draw time. Shares the canvas `sortIndex` z-order space with stickies/shapes/images (see
/// `BoardState.nextFrontCanvasIndex`), so it can sit in front of or behind any of them.
struct CanvasText: Sendable, Identifiable, Equatable {
    let id: UUID
    var cardID: Card.ID
    /// The text body. An empty body is auto-deleted on edit-commit (see `TextService.editing`), so a
    /// persisted `CanvasText` always carries content.
    var content: String
    /// Centre anchor (the same convention as every other canvas object).
    var position: CanvasPosition
    /// Width/height set manually by dragging; clamped via `TextSize`.
    var size: TextSize
    var style: CanvasTextStyle
    /// Stacking order within a card's canvas — shared with stickies/shapes/images; higher draws in front.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        cardID: Card.ID,
        content: String,
        position: CanvasPosition,
        size: TextSize = .default,
        style: CanvasTextStyle = .default,
        sortIndex: Int
    ) {
        self.id = id
        self.cardID = cardID
        self.content = content
        self.position = position
        self.size = size
        self.style = style
        self.sortIndex = sortIndex
    }
}

/// Where and how big a free-text object sits on a canvas — its centre `position` plus `size`.
/// Bundling the two keeps creation APIs (`TextService.adding`) to a single geometry argument.
/// Mirrors `ShapePlacement` / `StickyPlacement`.
struct TextPlacement: Sendable, Equatable {
    var position: CanvasPosition
    var size: TextSize
}
