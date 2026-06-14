import Foundation

/// Creates a free-text object on a card's canvas. `content` may be empty at creation — the palette
/// drop creates an empty text object and immediately enters inline editing (an empty body is
/// auto-deleted on edit-commit, see `TextService.editing`), so no non-empty *lower* guard here.
/// The *upper* bound still applies (the MCP `canvas_text_add` tool can hand an unbounded string),
/// using the same `stickyContent` cap as the sibling sticky requests. (ticket C5994D2A)
struct AddTextRequest: ValidatableRequest {
    let cardID: UUID
    let content: String
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double

    func validate() throws {
        try ContentSizeValidation.validate(stickyContent: content)
        // `positionX`/`positionY` flow unclamped into `CanvasPosition`; reject non-finite up front so
        // a boundary-less MCP caller (`canvas_text_add`) cannot persist NaN/Inf (ticket 4FD6D166).
        // `width`/`height` are clamped on the entity `init`.
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
