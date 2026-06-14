import Foundation

/// Service for canvas free-text objects. Mirrors `ShapeService`: the imperative verbs own the
/// `repository.mutate` boundary (Shape 1); the pure transforms compute and return a new `BoardState`
/// without persisting. Texts share the canvas `sortIndex` z-order with stickies/shapes/images, so
/// `adding` / `bringingToFront` / `sendingToBack` number against `BoardState.nextFrontCanvasIndex`.
final class TextService: TextServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol

    init(repository: any BoardRepositoryProtocol) {
        self.repository = repository
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func add(content: String, placement: TextPlacement, toCardCanvas cardID: Card.ID) async throws -> BoardState {
        try await repository.mutate { state in
            self.adding(content: content, placement: placement, toCardCanvas: cardID, in: state)
        }
    }

    func duplicate(id: CanvasText.ID, at position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.duplicating(id: id, at: position, in: state) }
    }

    func edit(id: CanvasText.ID, content: String) async throws -> BoardState {
        try await repository.mutate { state in try self.editing(id: id, content: content, in: state) }
    }

    func move(id: CanvasText.ID, to position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.moving(id: id, to: position, in: state) }
    }

    func resize(id: CanvasText.ID, to placement: TextPlacement) async throws -> BoardState {
        try await repository.mutate { state in try self.resizing(id: id, to: placement, in: state) }
    }

    func setColor(id: CanvasText.ID, colorHex: String) async throws -> BoardState {
        try await repository.mutate { state in try self.settingColor(id: id, colorHex: colorHex, in: state) }
    }

    func setFontSize(id: CanvasText.ID, fontSize: Double) async throws -> BoardState {
        try await repository.mutate { state in try self.settingFontSize(id: id, fontSize: fontSize, in: state) }
    }

    func bringToFront(id: CanvasText.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.bringingToFront(id: id, in: state) }
    }

    func sendToBack(id: CanvasText.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.sendingToBack(id: id, in: state) }
    }

    func delete(id: CanvasText.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms

    func adding(content: String, placement: TextPlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState {
        var state = state
        let text = CanvasText(
            cardID: cardID,
            content: content,
            position: placement.position,
            size: placement.size,
            sortIndex: state.nextFrontCanvasIndex(forCard: cardID)
        )
        state.texts.append(text)
        return state
    }

    /// Copies an existing text object to `position`, preserving its content, size, and style. The copy
    /// is numbered to the front of the card's canvas (`nextFrontCanvasIndex`) and gets a fresh id —
    /// mirrors `StickyService.duplicating`. Backs ⌘C/⌘V paste of a selected text.
    func duplicating(id: CanvasText.ID, at position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let source = state.texts[try state.requireIndex(of: id, in: \.texts, entityKind: "Text")]
        let copy = CanvasText(
            cardID: source.cardID,
            content: source.content,
            position: position,
            size: source.size,
            style: source.style,
            sortIndex: state.nextFrontCanvasIndex(forCard: source.cardID)
        )
        state.texts.append(copy)
        return state
    }

    /// Commits an edit. An **empty** body (after trimming whitespace) auto-deletes the text object —
    /// the canvas must never carry a blank free-text object (ticket 7C1D6316 決め事 2). A non-empty
    /// body is stored verbatim.
    func editing(id: CanvasText.ID, content: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        if content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.texts.remove(at: idx)
            return state
        }
        state.texts[idx].content = content
        return state
    }

    func moving(id: CanvasText.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        state.texts[idx].position = position
        return state
    }

    func resizing(id: CanvasText.ID, to placement: TextPlacement, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        // Re-construct `TextSize` through its initializer so the dimensions are re-clamped.
        state.texts[idx].size = TextSize(width: placement.size.width, height: placement.size.height)
        state.texts[idx].position = placement.position
        return state
    }

    func settingColor(id: CanvasText.ID, colorHex: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        state.texts[idx].style.colorHex = colorHex
        return state
    }

    func settingFontSize(id: CanvasText.ID, fontSize: Double, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        // Re-construct through the initializer so the font size is clamped to the valid range.
        state.texts[idx].style = CanvasTextStyle(
            colorHex: state.texts[idx].style.colorHex,
            fontSize: fontSize
        )
        return state
    }

    func bringingToFront(id: CanvasText.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        let cardID = state.texts[idx].cardID
        state.texts[idx].sortIndex = state.nextFrontCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func sendingToBack(id: CanvasText.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.texts, entityKind: "Text")
        let cardID = state.texts[idx].cardID
        state.texts[idx].sortIndex = state.nextBackCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func deleting(id: CanvasText.ID, from state: BoardState) throws -> BoardState {
        guard state.texts.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Text", id: id)
        }
        var state = state
        state.texts.removeAll { $0.id == id }
        return state
    }
}
