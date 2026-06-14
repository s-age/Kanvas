final class RenameColumnUseCaseImpl: AsyncUseCase, Sendable {
    private let columnService: any ColumnServiceProtocol
    private let mapper: BoardResponseMapper

    init(columnService: any ColumnServiceProtocol) {
        self.columnService = columnService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: RenameColumnRequest) async throws -> BoardResponse {
        let newState = try await columnService.rename(
            id: request.columnID,
            to: request.title.trimmingCharacters(in: .whitespaces)
        )
        return mapper.toBoardResponse(newState)
    }
}
