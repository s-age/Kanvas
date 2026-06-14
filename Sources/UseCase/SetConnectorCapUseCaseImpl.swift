final class SetConnectorCapUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorCapRequest) async throws -> BoardMutationResponse {
        // validate() guarantees the raw value resolves.
        let cap = ConnectorEndpointCap(rawValue: request.cap) ?? .arrow
        let newState = try await connectorService.setCap(id: request.connectorID, cap: cap)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
