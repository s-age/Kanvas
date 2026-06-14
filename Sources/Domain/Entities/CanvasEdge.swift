/// Which side of a sticky a connector attaches to. The endpoint is always that edge's midpoint,
/// so a connector keeps extending from the same edge as its sticky moves or resizes. The raw value
/// is the cross-layer vocabulary shared with the persisted `ConnectorDTO.sourceEdge`/`targetEdge`
/// and the Presentation `CanvasEdgeResponse` — never rename a case's raw value or stored
/// connectors stop decoding.
enum CanvasEdge: String, Sendable, CaseIterable, Equatable {
    case top
    case bottom
    case left
    case right
}
