final class AddColumnUseCaseImpl: AsyncUseCase, Sendable {
    private let columnService: any ColumnServiceProtocol
    private let mapper: BoardResponseMapper

    init(columnService: any ColumnServiceProtocol) {
        self.columnService = columnService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddColumnRequest) async throws -> BoardResponse {
        let newState = try await columnService.add(
            title: request.title.trimmingCharacters(in: .whitespaces)
        )
        return mapper.toBoardResponse(newState)
    }
}
