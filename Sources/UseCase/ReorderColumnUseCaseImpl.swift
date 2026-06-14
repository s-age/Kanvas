final class ReorderColumnUseCaseImpl: AsyncUseCase, Sendable {
    private let columnService: any ColumnServiceProtocol
    private let mapper: BoardResponseMapper

    init(columnService: any ColumnServiceProtocol) {
        self.columnService = columnService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: ReorderColumnRequest) async throws -> BoardResponse {
        let newState = try await columnService.reorder(
            id: request.columnID,
            before: request.beforeColumnID
        )
        return mapper.toBoardResponse(newState)
    }
}
