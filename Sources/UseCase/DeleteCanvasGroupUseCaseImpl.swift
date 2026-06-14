import Foundation

final class DeleteCanvasGroupUseCaseImpl: AsyncUseCase, Sendable {
    private let groupService: any CanvasGroupServiceProtocol
    private let mapper: BoardResponseMapper

    init(groupService: any CanvasGroupServiceProtocol) {
        self.groupService = groupService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: DeleteCanvasGroupRequest) async throws -> BoardMutationResponse {
        let newState = try await groupService.deleteGroup(ids: request.ids)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
