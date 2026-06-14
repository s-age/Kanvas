import Foundation

final class ShapeService: ShapeServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol

    init(repository: any BoardRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func add(spec: ShapeSpec, placement: ShapePlacement,
             toCardCanvas cardID: Card.ID) async throws -> BoardState {
        try await repository.mutate { state in
            self.adding(spec: spec, placement: placement, toCardCanvas: cardID, in: state)
        }
    }

    func move(id: CanvasShape.ID, to position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.moving(id: id, to: position, in: state) }
    }

    func resize(id: CanvasShape.ID, to placement: ShapePlacement, lineRising: Bool?) async throws -> BoardState {
        try await repository.mutate { state in
            try self.resizing(id: id, to: placement, lineRising: lineRising, in: state)
        }
    }

    func setStrokeColor(id: CanvasShape.ID, colorHex: String) async throws -> BoardState {
        try await repository.mutate { state in try self.settingStrokeColor(id: id, colorHex: colorHex, in: state) }
    }

    func setFillColor(id: CanvasShape.ID, colorHex: String?) async throws -> BoardState {
        try await repository.mutate { state in try self.settingFillColor(id: id, colorHex: colorHex, in: state) }
    }

    func setStrokeWidth(id: CanvasShape.ID, width: Double) async throws -> BoardState {
        try await repository.mutate { state in try self.settingStrokeWidth(id: id, width: width, in: state) }
    }

    func bringToFront(id: CanvasShape.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.bringingToFront(id: id, in: state) }
    }

    func sendToBack(id: CanvasShape.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.sendingToBack(id: id, in: state) }
    }

    func delete(id: CanvasShape.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms (UNCHANGED)

    func adding(spec: ShapeSpec, placement: ShapePlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState {
        var state = state
        let shape = CanvasShape(
            cardID: cardID,
            kind: spec.kind,
            topology: spec.topology,
            position: placement.position,
            size: placement.size,
            sortIndex: state.nextFrontCanvasIndex(forCard: cardID)
        )
        state.shapes.append(shape)
        return state
    }

    func moving(id: CanvasShape.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        state.shapes[idx].position = position
        return state
    }

    func resizing(id: CanvasShape.ID, to placement: ShapePlacement,
                  lineRising: Bool?, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        // Clamp rule is selected by the stored topology, not the visual kind — segment shapes keep a
        // usable minimum length; box shapes (filled/stroked outline) keep a usable minimum side.
        let isSegment = state.shapes[idx].topology == .segment
        state.shapes[idx].size = isSegment
            ? lineSize(placement.size)
            : ShapeSize(width: max(placement.size.width, ShapeSize.minFilledSide),
                        height: max(placement.size.height, ShapeSize.minFilledSide))
        state.shapes[idx].position = placement.position
        if let lineRising {
            state.shapes[idx].lineRising = lineRising
        }
        return state
    }

    /// Enforces the line minimum-length rule: if the box diagonal is below `minLineLength`, scale
    /// the box up about its centre (preserving direction); a fully-degenerate box defaults to a
    /// horizontal minimum-length line.
    private func lineSize(_ size: ShapeSize) -> ShapeSize {
        let diagonal = (size.width * size.width + size.height * size.height).squareRoot()
        guard diagonal < ShapeSize.minLineLength else { return size }
        guard diagonal > 0.0001 else { return ShapeSize(width: ShapeSize.minLineLength, height: 0) }
        let scale = ShapeSize.minLineLength / diagonal
        return ShapeSize(width: size.width * scale, height: size.height * scale)
    }

    func settingStrokeColor(id: CanvasShape.ID, colorHex: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        state.shapes[idx].style.strokeColorHex = colorHex
        return state
    }

    func settingFillColor(id: CanvasShape.ID, colorHex: String?, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        // `nil` is the "no fill" sentinel — stored verbatim so the shape draws stroke-only.
        state.shapes[idx].style.fillColorHex = colorHex
        return state
    }

    func settingStrokeWidth(id: CanvasShape.ID, width: Double, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        // Re-construct through the initializer so the width is clamped to the valid range.
        state.shapes[idx].style = CanvasShapeStyle(
            strokeColorHex: state.shapes[idx].style.strokeColorHex,
            fillColorHex: state.shapes[idx].style.fillColorHex,
            strokeWidth: width
        )
        return state
    }

    func bringingToFront(id: CanvasShape.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        let cardID = state.shapes[idx].cardID
        // Shared canvas z-order: front of *all* items (stickies + shapes).
        state.shapes[idx].sortIndex = state.nextFrontCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func sendingToBack(id: CanvasShape.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.shapes, entityKind: "Shape")
        let cardID = state.shapes[idx].cardID
        state.shapes[idx].sortIndex = state.nextBackCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func deleting(id: CanvasShape.ID, from state: BoardState) throws -> BoardState {
        guard state.shapes.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Shape", id: id)
        }
        var state = state
        state.shapes.removeAll { $0.id == id }
        return state
    }
}
