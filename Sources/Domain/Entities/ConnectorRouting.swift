/// The path a connector takes between its two edge midpoints — a direct line, an orthogonal elbow
/// (right-angle), or a smooth curve. The raw value is the cross-layer vocabulary shared with
/// `ConnectorDTO.routing` and the Presentation `ConnectorRoutingResponse` — never rename a case's
/// raw value or stored connectors stop decoding.
enum ConnectorRouting: String, Sendable, CaseIterable, Equatable {
    case straight
    case elbow
    case curve
}
