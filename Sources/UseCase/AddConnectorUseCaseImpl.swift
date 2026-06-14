import Foundation

final class AddConnectorUseCaseImpl: AsyncUseCase, Sendable {
    private let connectorService: any ConnectorServiceProtocol
    private let mapper: BoardResponseMapper

    init(connectorService: any ConnectorServiceProtocol) {
        self.connectorService = connectorService
        self.mapper = BoardResponseMapper()
    }

    func execute(_ request: AddConnectorRequest) async throws -> BoardMutationResponse {
        // validate() guarantees both raw edges resolve.
        let sourceEdge = CanvasEdge(rawValue: request.sourceEdge) ?? .right
        let targetEdge = CanvasEdge(rawValue: request.targetEdge) ?? .left
        // Placement for the "drop on empty" path; ignored when an existing target is supplied. The
        // service resolves the target (existing vs. new sticky) and commits both the sticky and the
        // connector in one mutation (one undo).
        let newStickyPlacement = StickyPlacement(
            position: CanvasPosition(x: request.newStickyX, y: request.newStickyY),
            size: StickySize(width: request.newStickyWidth, height: request.newStickyHeight)
        )
        let newState = try await connectorService.add(
            cardID: request.cardID,
            seed: ConnectorSeed(
                sourceStickyID: request.sourceStickyID, sourceEdge: sourceEdge, targetEdge: targetEdge,
                existingTargetStickyID: request.existingTargetStickyID,
                newStickyPlacement: newStickyPlacement,
                strokeColorHex: request.strokeColorHex
            )
        )
        return mapper.toBoardMutation(newState, affectedCardID: request.cardID)
    }
}
