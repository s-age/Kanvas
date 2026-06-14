import Foundation

final class SearchCardsUseCaseImpl: SearchCardsUseCase, Sendable {
    private let boardManagement: any BoardManagementServiceProtocol

    init(boardManagement: any BoardManagementServiceProtocol) {
        self.boardManagement = boardManagement
    }

    func execute(query: String) async throws -> Set<UUID> {
        try await boardManagement.matchingCardIDs(query: query)
    }
}
