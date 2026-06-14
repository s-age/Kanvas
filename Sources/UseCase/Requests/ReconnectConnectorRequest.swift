import Foundation

/// Re-attaches a connector's endpoint(s). Each side (`source` / `target`) is either fully specified
/// (both `stickyID` and `edge`) or fully omitted (both `nil`) — a half-specified side is an error.
/// At least one side must be specified (an all-`nil` edit is a no-op, rejected loudly like the MCP
/// `emptyConnectorEdit`). To change only an endpoint's edge, pass that side with the **same**
/// `stickyID` and the new edge. Edges cross the boundary as `CanvasEdge` raw values (Presentation /
/// the MCP gateway never import the domain enum). The self-loop rule (the reconnected
/// `sourceStickyID == targetStickyID` is rejected) needs the other side's live value, so it is a
/// domain check inside `ConnectorService.reconnecting`, not here.
struct ReconnectConnectorRequest: ValidatableRequest {
    let connectorID: UUID
    let sourceStickyID: UUID?
    let sourceEdge: String?
    let targetStickyID: UUID?
    let targetEdge: String?

    init(connectorID: UUID,
         sourceStickyID: UUID? = nil, sourceEdge: String? = nil,
         targetStickyID: UUID? = nil, targetEdge: String? = nil) {
        self.connectorID = connectorID
        self.sourceStickyID = sourceStickyID
        self.sourceEdge = sourceEdge
        self.targetStickyID = targetStickyID
        self.targetEdge = targetEdge
    }

    /// `true` when both the sticky id and edge of the source side are present (a fully-specified
    /// side). Used to assemble the domain `ConnectorEndpoint` in the use case.
    var hasSource: Bool { sourceStickyID != nil && sourceEdge != nil }
    /// `true` when both the sticky id and edge of the target side are present.
    var hasTarget: Bool { targetStickyID != nil && targetEdge != nil }

    func validate() throws {
        // Each side is all-or-nothing: a half-specified side (one of id/edge) is rejected.
        guard (sourceStickyID == nil) == (sourceEdge == nil),
              (targetStickyID == nil) == (targetEdge == nil) else {
            throw ValidationError.invalidConnectorEdge
        }
        // At least one side must be specified — an all-nil edit is a no-op.
        guard hasSource || hasTarget else {
            throw ValidationError.invalidConnectorEdge
        }
        // Any provided edge must resolve to a valid CanvasEdge raw value.
        if let sourceEdge, CanvasEdge(rawValue: sourceEdge) == nil {
            throw ValidationError.invalidConnectorEdge
        }
        if let targetEdge, CanvasEdge(rawValue: targetEdge) == nil {
            throw ValidationError.invalidConnectorEdge
        }
    }
}
