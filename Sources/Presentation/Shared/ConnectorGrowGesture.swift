import Foundation

/// A connector-grow gesture's result, assembled by the canvas and handed to the ViewModel. Bundles
/// the source endpoint, the chosen target edge, and the drop location so the grow call stays a
/// single argument. `existingTargetStickyID` non-nil links that sticky; nil grows a new sticky at
/// (`dropWorldX`, `dropWorldY`). Edges are `CanvasEdgeResponse` raw values. Named a *gesture* (not
/// a *request*) to mark it as the Presentation interaction payload, distinct from the UseCase-layer
/// `AddConnectorRequest`.
struct ConnectorGrowGesture: Equatable, Sendable {
    let sourceStickyID: UUID
    let sourceEdge: String
    let targetEdge: String
    let existingTargetStickyID: UUID?
    let dropWorldX: Double
    let dropWorldY: Double
}
