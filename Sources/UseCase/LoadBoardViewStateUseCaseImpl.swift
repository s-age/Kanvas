import Foundation

/// Loads the full state a board refresh publishes — board, picker list, and the open card's detail —
/// from a **single** store read (ticket 8DCB811D). The external-change watcher path previously paid
/// three separate flock + decode round-trips (`LoadActiveBoard` → `ListBoards` →
/// `LoadCardDetail → loadActiveBoard`); this maps all three Responses off the one `BoardState` +
/// catalog the Domain Service returns from one exclusive section.
final class LoadBoardViewStateUseCaseImpl: AsyncUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: LoadBoardViewStateRequest) async throws -> BoardViewStateResponse {
        let snapshot = try await boardManagement.bootstrapActiveBoardWithCatalog()
        let trimmedQuery = request.searchQuery?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return BoardViewStateResponse(
            board: mapper.toBoardResponse(snapshot.state),
            boardList: mapper.toBoardListResponse(boards: snapshot.boards, activeBoardID: snapshot.activeBoardID),
            cardDetail: request.openCardID.flatMap {
                mapper.toCardDetailResponse(cardID: $0, from: snapshot.state)
            },
            // Apply the active filter over the **same** decoded state — no second store read (PR #123
            // r2-1). A blank/absent query carries no filter, so `matchedCardIDs` stays `nil` (the
            // ViewModel's "show every card" sentinel) rather than the whole-board set `CardQuery`
            // returns for a blank query.
            matchedCardIDs: trimmedQuery.isEmpty
                ? nil
                : boardManagement.matchingCardIDs(in: snapshot.state, query: trimmedQuery),
            matchedQuery: trimmedQuery
        )
    }
}
