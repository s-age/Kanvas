import Foundation

final class MoveCanvasGroupUseCaseImpl: AsyncUseCase, Sendable {
    private let groupService: any CanvasGroupServiceProtocol
    private let mapper: BoardResponseMapper

    init(groupService: any CanvasGroupServiceProtocol) {
        self.groupService = groupService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: MoveCanvasGroupRequest) async throws -> BoardMutationResponse {
        let movements = request.movements.map {
            CanvasItemMovement(id: $0.id, position: CanvasPosition(x: $0.positionX, y: $0.positionY))
        }
        let newState = try await groupService.moveGroup(movements)
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
