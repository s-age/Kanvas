/// How a connector's target end is drawn — a plain line tip or an arrowhead. The raw value is the
/// cross-layer vocabulary shared with `ConnectorDTO.cap` and the Presentation
/// `ConnectorCapResponse` — never rename a case's raw value or stored connectors stop decoding.
enum ConnectorEndpointCap: String, Sendable, CaseIterable, Equatable {
    case line
    case arrow
}
