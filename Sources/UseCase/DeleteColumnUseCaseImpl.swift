final class DeleteColumnUseCaseImpl: AsyncUseCase, Sendable {
    private let columnService: any ColumnServiceProtocol
    private let mapper: BoardResponseMapper

    init(columnService: any ColumnServiceProtocol) {
        self.columnService = columnService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteColumnRequest) async throws -> BoardResponse {
        let newState = try await columnService.delete(id: request.columnID)
        return mapper.toBoardResponse(newState)
    }
}
