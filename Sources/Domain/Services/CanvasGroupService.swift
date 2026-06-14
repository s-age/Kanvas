import Foundation

/// Group move / delete over a multi-selection of canvas items. Holds the board repository (it owns
/// the single `repository.mutate` boundary) plus the four per-kind sibling services, whose **pure**
/// transforms it composes inside that one mutation — the sanctioned multi-entity composition (see
/// `arch-domain-services.md` → "Multi-entity composition"). Reusing the siblings' transforms keeps
/// each kind's rules single-sourced: a sticky delete still cascades its connectors, an image keeps
/// its sidecar asset, etc. Routing each id to its kind is `BoardState.canvasItemKind(of:)`.
final class CanvasGroupService: CanvasGroupServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    private let stickyService: any StickyServiceProtocol
    private let shapeService: any ShapeServiceProtocol
    private let imageService: any CanvasImageServiceProtocol
    private let textService: any TextServiceProtocol
    private let connectorService: any ConnectorServiceProtocol

    init(repository: any BoardRepositoryProtocol,
         stickyService: any StickyServiceProtocol,
         shapeService: any ShapeServiceProtocol,
         imageService: any CanvasImageServiceProtocol,
         textService: any TextServiceProtocol,
         connectorService: any ConnectorServiceProtocol) {
        self.repository = repository
        self.stickyService = stickyService
        self.shapeService = shapeService
        self.imageService = imageService
        self.textService = textService
        self.connectorService = connectorService
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func moveGroup(_ movements: [CanvasItemMovement]) async throws -> BoardState {
        try await repository.mutate { state in try self.movingGroup(movements, in: state) }
    }

    func deleteGroup(ids: [UUID]) async throws -> BoardState {
        try await repository.mutate { state in try self.deletingGroup(ids: ids, in: state) }
    }

    // MARK: Pure transforms

    func movingGroup(_ movements: [CanvasItemMovement], in state: BoardState) throws -> BoardState {
        var working = state
        for movement in movements {
            // Resolve the kind against the *working* state each step so the routing reflects any
            // prior mutation in this batch. A vanished id (`nil`) or a connector (no geometry) is
            // skipped; the matched kind's transform never throws `notFound` here because presence was
            // just confirmed.
            switch working.canvasItemKind(of: movement.id) {
            case .sticky:
                working = try stickyService.moving(id: movement.id, to: movement.position, in: working)
            case .shape:
                working = try shapeService.moving(id: movement.id, to: movement.position, in: working)
            case .image:
                working = try imageService.moving(id: movement.id, to: movement.position, in: working)
            case .text:
                working = try textService.moving(id: movement.id, to: movement.position, in: working)
            case .connector, .none:
                continue
            }
        }
        return working
    }

    func deletingGroup(ids: [UUID], in state: BoardState) throws -> BoardState {
        var working = state
        for id in ids {
            // Re-resolve per id against the working state so a connector already cascaded away by an
            // earlier sticky delete in this same batch resolves to `nil` and is skipped (rather than
            // throwing `notFound`). An id that was never present is likewise tolerated.
            switch working.canvasItemKind(of: id) {
            case .sticky:
                working = try stickyService.deleting(id: id, from: working)
            case .shape:
                working = try shapeService.deleting(id: id, from: working)
            case .image:
                working = try imageService.deleting(id: id, from: working)
            case .text:
                working = try textService.deleting(id: id, from: working)
            case .connector:
                working = try connectorService.deleting(id: id, from: working)
            case .none:
                continue
            }
        }
        return working
    }
}
