final class EditBoardSettingsUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    /// Applies the board's settings **and** its columns' colours / completion flag in **one**
    /// mutation, so a single "Save" is one undo entry and one disk write.
    func execute(_ request: EditBoardSettingsRequest) async throws -> BoardResponse {
        let settings = request.toDomain()
        let columns = request.columns.map { column in
            ColumnAppearanceUpdate(
                id: column.id,
                colors: ColumnColors(
                    headerColorHex: column.headerColorHex,
                    headerTextColorHex: column.headerTextColorHex,
                    bodyColorHex: column.bodyColorHex,
                    headerBorderColorHex: column.headerBorderColorHex,
                    bodyBorderColorHex: column.bodyBorderColorHex,
                    indicatorColorHex: column.indicatorColorHex
                ),
                isCompletionColumn: column.isCompletionColumn
            )
        }
        let newState = try await boardManagement.editBoardSettings(
            boardID: request.boardID, settings: settings, columns: columns
        )
        return mapper.toBoardResponse(newState)
    }
}
