import Foundation

final class LoadCardDetailUseCaseImpl: LoadCardDetailUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol
    private let mapper: BoardResponseMapper

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
        self.mapper = BoardResponseMapper()
    }

    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        let state = try await boardManagement.loadActiveBoard()
        return mapper.toCardDetailResponse(cardID: cardID, from: state)
    }
}
