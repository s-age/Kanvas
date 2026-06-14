final class EditColumnAppearanceUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    /// Edits one column's colours + completion flag in a single atomic mutation — one undo entry,
    /// no lost-update window for sibling columns (see `editColumnAppearance` on the service).
    func execute(_ request: EditColumnAppearanceRequest) async throws -> BoardResponse {
        let newState = try await boardManagement.editColumnAppearance(
            columnID: request.columnID, edit: request.toDomain()
        )
        return mapper.toBoardResponse(newState)
    }
}
