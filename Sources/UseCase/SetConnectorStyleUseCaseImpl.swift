import Foundation

/// Applies a connector restyle — any subset of cap / routing / stroke colour / stroke width — as
/// **one** repository mutation: every provided field validates before anything commits, and the
/// whole edit is a single undo step / file-lock round-trip. The single-field `SetConnector*`
/// use cases stay for the app's inspector (one field per gesture); this one serves multi-field
/// editors like the MCP `canvas_connector_edit` tool, which would otherwise partially apply when
/// a later field fails validation.
final class SetConnectorStyleUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorStyleRequest) async throws -> BoardMutationResponse {
        // validate() guarantees every provided raw value resolves. The service applies the whole
        // subset in one mutation, so an invalid late field can never leave the earlier ones applied.
        let cap = request.cap.flatMap(ConnectorEndpointCap.init(rawValue:))
        let routing = request.routing.flatMap(ConnectorRouting.init(rawValue:))
        let newState = try await connectorService.setStyle(
            id: request.connectorID,
            change: ConnectorStyleChange(
                cap: cap,
                routing: routing,
                strokeColorHex: request.strokeColorHex,
                strokeWidth: request.strokeWidth
            )
        )
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
