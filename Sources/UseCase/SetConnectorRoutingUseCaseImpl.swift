final class SetConnectorRoutingUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorRoutingRequest) async throws -> BoardMutationResponse {
        // validate() guarantees the raw value resolves.
        let routing = ConnectorRouting(rawValue: request.routing) ?? .straight
        let newState = try await connectorService.setRouting(id: request.connectorID, routing: routing)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
