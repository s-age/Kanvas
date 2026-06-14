import Foundation

struct AddStickyRequest: ValidatableRequest {
    let cardID: UUID
    let content: String
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double
    /// Background **fill** ("RRGGBB") from the chosen palette preset, or `nil` to inherit the
    /// board's free/task default fill. Named to distinguish it from the text colour.
    let fillColorHex: String?

    // A blank sticky is valid (an empty note on the canvas), so only the upper bound is checked.
    // A present fill colour must be a 6-digit RGB hex (mirrors the add-connector stroke-colour
    // flow); `nil` inherits the board default, so it is skipped.
    func validate() throws {
        try ContentSizeValidation.validate(stickyContent: content)
        // `positionX`/`positionY` flow unclamped into `CanvasPosition`; reject non-finite up front so
        // a boundary-less MCP caller (`canvas_sticky_add`) cannot persist NaN/Inf (ticket 4FD6D166).
        // `width`/`height` are clamped on the `StickySize` entity `init`.
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
        if let fillColorHex {
            try LabelValidation.validate(colorHex: fillColorHex)
        }
    }
}
