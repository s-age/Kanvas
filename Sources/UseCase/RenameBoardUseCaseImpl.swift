final class RenameBoardUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: RenameBoardRequest) async throws -> BoardListResponse {
        let catalog = try await boardManagement.renameBoard(
            id: request.boardID,
            title: request.title.trimmingCharacters(in: .whitespaces)
        )
        return mapper.toBoardListResponse(boards: catalog.boards, activeBoardID: catalog.activeBoardID)
    }
}
