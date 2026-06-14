final class AddBoardUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddBoardRequest) async throws -> BoardResponse {
        let title = request.title.trimmingCharacters(in: .whitespaces)
        let state = try await boardManagement.addBoard(title: title)
        return mapper.toBoardResponse(state)
    }
}
