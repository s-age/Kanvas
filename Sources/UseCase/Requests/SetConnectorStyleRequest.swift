import Foundation

/// One connector restyle; nil fields keep their current value. Bundling the four style fields lets
/// a multi-field edit (the MCP `canvas_connector_edit` path) validate everything **before** any
/// write — chaining the four single-field use cases instead would commit the early fields and then
/// throw on a later one's validation, leaving a partial restyle behind a reported failure.
struct SetConnectorStyleRequest: ValidatableRequest {
    let connectorID: UUID
    /// `ConnectorEndpointCap` raw value ("line" / "arrow") — validated here since callers
    /// never import the domain enum (mirrors `SetConnectorCapRequest`).
    let cap: String?
    /// `ConnectorRouting` raw value ("straight" / "elbow" / "curve").
    let routing: String?
    let strokeColorHex: String?
    /// Bounds-validated here (when present) against the same range as `SetConnectorStrokeWidthRequest`
    /// — this bundled request is the primary MCP edit surface, so the out-of-range guard must hold on
    /// it too, not only on the single-field setter.
    let strokeWidth: Double?

    func validate() throws {
        if let cap, ConnectorEndpointCap(rawValue: cap) == nil {
            throw ValidationError.invalidConnectorCap
        }
        if let routing, ConnectorRouting(rawValue: routing) == nil {
            throw ValidationError.invalidConnectorRouting
        }
        if let strokeColorHex {
            try LabelValidation.validate(colorHex: strokeColorHex)
        }
        if let strokeWidth {
            try NumericBoundsValidation.validate(
                strokeWidth: strokeWidth, in: ConnectorStyle.minStrokeWidth...ConnectorStyle.maxStrokeWidth
            )
        }
    }
}
