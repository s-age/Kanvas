final class DeleteConnectorUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteConnectorRequest) async throws -> BoardMutationResponse {
        let newState = try await connectorService.delete(id: request.connectorID)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
