import Foundation

/// Re-attaches a connector's endpoint(s) — moving an end to a different sticky / edge — as one
/// repository mutation (one undo step). Mirrors the bundled `SetConnectorStyle` shape: the request
/// validates the edge raw values up front, the service applies both sides in one mutation, and the
/// self-loop / sticky-existence rules live in the domain transform.
final class ReconnectConnectorUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ReconnectConnectorRequest) async throws -> BoardMutationResponse {
        // validate() guarantees each provided side carries both a sticky id and a resolvable edge,
        // and that at least one side is provided — so the force-unwraps below are sound.
        let source = request.hasSource
            ? ConnectorEndpoint(stickyID: request.sourceStickyID!, edge: CanvasEdge(rawValue: request.sourceEdge!)!)
            : nil
        let target = request.hasTarget
            ? ConnectorEndpoint(stickyID: request.targetStickyID!, edge: CanvasEdge(rawValue: request.targetEdge!)!)
            : nil
        let newState = try await connectorService.reconnect(
            id: request.connectorID, source: source, target: target
        )
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
