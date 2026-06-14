import Foundation

/// Sets (or clears) a connector's waypoint offset — the central deformation handle's shift from the
/// midpoint of the two endpoint edge midpoints. Passing both `offsetX` and `offsetY` sets the
/// waypoint; passing neither (both `nil`) clears it back to the automatic route. A half-specified
/// offset (one axis only) is rejected. The offset crosses the boundary as raw `Double`s
/// (Presentation never imports the domain `CanvasOffset`).
struct SetConnectorWaypointRequest: ValidatableRequest {
    let connectorID: UUID
    let offsetX: Double?
    let offsetY: Double?

    init(connectorID: UUID, offsetX: Double? = nil, offsetY: Double? = nil) {
        self.connectorID = connectorID
        self.offsetX = offsetX
        self.offsetY = offsetY
    }

    /// `true` when both axes are present — a fully-specified offset. Used to assemble the domain
    /// `CanvasOffset` in the use case (the `false` case clears the waypoint).
    var hasOffset: Bool { offsetX != nil && offsetY != nil }

    func validate() throws {
        // All-or-nothing: a half-specified offset (one axis) is incoherent.
        guard (offsetX == nil) == (offsetY == nil) else {
            throw ValidationError.invalidConnectorWaypoint
        }
        // A present offset component must be finite — `CanvasOffset` clamps nothing, so a NaN/Inf
        // would otherwise persist straight into the store (ticket 4FD6D166).
        try NumericBoundsValidation.validate(finiteCoordinates: offsetX, offsetY)
    }
}
