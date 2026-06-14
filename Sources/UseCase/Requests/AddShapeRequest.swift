import Foundation

struct AddShapeRequest: ValidatableRequest {
    let cardID: UUID
    /// Open visual token from the Presentation registry (e.g. "rectangle" / "triangle").
    let kind: String
    /// `ShapeTopology` raw value ("box" | "segment"), supplied by the registry definition.
    let topology: String
    let positionX: Double
    let positionY: Double
    let width: Double
    let height: Double

    func validate() throws {
        guard !kind.isEmpty else { throw ValidationError.invalidShapeKind }
        guard ShapeTopology(rawValue: topology) != nil else {
            throw ValidationError.invalidShapeTopology
        }
        // `positionX`/`positionY` flow unclamped into `CanvasPosition`; reject non-finite up front so
        // a boundary-less MCP caller cannot persist NaN/Inf (ticket 4FD6D166).
        // `width`/`height` are clamped on the entity `init`.
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
