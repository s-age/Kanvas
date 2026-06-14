import Foundation

/// Sets (or clears) a connector's waypoint offset as one repository mutation (one undo step). The
/// request validates the all-or-nothing offset shape up front; this maps it to the domain
/// `CanvasOffset` (or `nil` to clear) and delegates to `ConnectorService.setWaypoint`.
final class SetConnectorWaypointUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorWaypointRequest) async throws -> BoardMutationResponse {
        // validate() guarantees the offset is all-or-nothing, so this is sound.
        let offset = request.hasOffset
            ? CanvasOffset(dx: request.offsetX!, dy: request.offsetY!)
            : nil
        let newState = try await connectorService.setWaypoint(id: request.connectorID, offset: offset)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
