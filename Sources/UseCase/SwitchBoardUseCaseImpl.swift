final class SwitchBoardUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: SwitchBoardRequest) async throws -> BoardResponse {
        let state = try await boardManagement.switchBoard(to: request.boardID)
        return mapper.toBoardResponse(state)
    }
}
