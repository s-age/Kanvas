final class SetCompletionColumnUseCaseImpl: AsyncUseCase, Sendable {
    private let columnService: any ColumnServiceProtocol
    private let mapper: BoardResponseMapper

    init(columnService: any ColumnServiceProtocol) {
        self.columnService = columnService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SetCompletionColumnRequest) async throws -> BoardResponse {
        let newState = try await columnService.setCompletion(
            id: request.columnID,
            isCompletion: request.isCompletion
        )
        return mapper.toBoardResponse(newState)
    }
}
