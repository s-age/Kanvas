final class SetConnectorStrokeWidthUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetConnectorStrokeWidthRequest) async throws -> BoardMutationResponse {
        let newState = try await connectorService.setStrokeWidth(id: request.connectorID, width: request.width)
        return mapper.toBoardMutation(newState, affectedCardID: newState.ownerCardID(ofConnector: request.connectorID))
    }
}
