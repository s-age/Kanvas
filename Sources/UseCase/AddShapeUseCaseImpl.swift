final class AddShapeUseCaseImpl: AsyncUseCase, Sendable {
    private let shapeService: any ShapeServiceProtocol
    private let mapper: BoardResponseMapper

    init(shapeService: any ShapeServiceProtocol) {
        self.shapeService = shapeService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddShapeRequest) async throws -> BoardMutationResponse {
        // validate() checks kind is non-empty; topology is parsed exactly once below (no silent fallback).
        guard let topology = ShapeTopology(rawValue: request.topology) else {
            throw ValidationError.invalidShapeTopology
        }
        let placement = ShapePlacement(
            position: CanvasPosition(x: request.positionX, y: request.positionY),
            size: ShapeSize(width: request.width, height: request.height)
        )
        let newState = try await shapeService.add(
            spec: ShapeSpec(kind: request.kind, topology: topology),
            placement: placement,
            toCardCanvas: request.cardID
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
