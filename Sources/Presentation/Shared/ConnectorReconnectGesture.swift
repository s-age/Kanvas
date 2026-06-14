import Foundation

/// Which end of a connector a reconnect gesture moves.
enum ConnectorEndpointSide: Equatable, Sendable {
    case source
    case target
}

/// A connector-reconnect gesture's result, assembled by the canvas and handed to the ViewModel.
/// The dragged endpoint (`side`) moves to `newStickyID`'s `newEdge`; the other end is left as-is.
/// Edges are `CanvasEdgeResponse` raw values. Named a *gesture* (not a *request*) to mark it as the
/// Presentation interaction payload, distinct from the UseCase-layer `ReconnectConnectorRequest`.
struct ConnectorReconnectGesture: Equatable, Sendable {
    let connectorID: UUID
    let side: ConnectorEndpointSide
    let newStickyID: UUID
    let newEdge: String
}
