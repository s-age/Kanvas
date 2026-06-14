final class SetConnectorStrokeColorUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorStrokeColorRequest) async throws -> BoardMutationResponse {
        let newState = try await connectorService.setStrokeColor(id: request.connectorID, colorHex: request.colorHex)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
