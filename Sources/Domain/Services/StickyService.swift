import Foundation

final class StickyService: StickyServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    private let now: @Sendable () -> Date

    init(repository: any BoardRepositoryProtocol, now: @escaping @Sendable () -> Date = { Date() }) {
        self.repository = repository
        self.now = now
    }

    // MARK: Imperative verbs (own the mutate boundary)

    func add(content: String, placement: StickyPlacement, toCardCanvas cardID: Card.ID) async throws -> BoardState {
        try await repository.mutate { state in
            self.adding(content: content, placement: placement, toCardCanvas: cardID, in: state)
        }
    }

    func duplicate(id: Sticky.ID, at position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.duplicating(id: id, at: position, in: state) }
    }

    func edit(id: Sticky.ID, content: String) async throws -> BoardState {
        try await repository.mutate { state in try self.editing(id: id, content: content, in: state) }
    }

    func setTextColor(id: Sticky.ID, colorHex: String) async throws -> BoardState {
        try await repository.mutate { state in try self.settingTextColor(id: id, colorHex: colorHex, in: state) }
    }

    func setFillColor(id: Sticky.ID, fillColorHex: String?) async throws -> BoardState {
        try await repository.mutate { state in
            try self.settingFillColor(id: id, fillColorHex: fillColorHex, in: state)
        }
    }

    func setFontSize(id: Sticky.ID, fontSize: Double) async throws -> BoardState {
        try await repository.mutate { state in try self.settingFontSize(id: id, fontSize: fontSize, in: state) }
    }

    func setFrame(id: Sticky.ID, to size: StickySize, at position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.settingFrame(id: id, to: size, at: position, in: state) }
    }

    func move(id: Sticky.ID, to position: CanvasPosition) async throws -> BoardState {
        try await repository.mutate { state in try self.moving(id: id, to: position, in: state) }
    }

    func toggleLabel(stickyID: Sticky.ID, labelID: UUID) async throws -> BoardState {
        try await repository.mutate { state in try self.togglingLabel(stickyID: stickyID, labelID: labelID, in: state) }
    }

    func bringToFront(id: Sticky.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.bringingToFront(id: id, in: state) }
    }

    func sendToBack(id: Sticky.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.sendingToBack(id: id, in: state) }
    }

    func promote(id: Sticky.ID, toColumn columnID: Column.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.promoting(id: id, toColumn: columnID, in: state) }
    }

    func demote(id: Sticky.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.demoting(id: id, in: state) }
    }

    func delete(id: Sticky.ID) async throws -> BoardState {
        try await repository.mutate { state in try self.deleting(id: id, from: state) }
    }

    // MARK: Pure transforms

    func adding(content: String, placement: StickyPlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState {
        var state = state
        // A new sticky inherits the board's canvas defaults for text appearance (size always; colour
        // only when no explicit fill is given). When `placement.fillColorHex` *is* given (a palette
        // preset, or an MCP-specified colour), the text colour is auto-contrasted against that fill —
        // #333 on a light fill, #ddd on a dark one — so the content stays readable on any background.
        // Re-construction through `StickyTextStyle.init` re-clamps the font size to the valid range.
        let canvas = state.settings.canvas
        let textColorHex = placement.fillColorHex.map(ContrastColor.readableHex(onBackground:))
            ?? canvas.defaultTextColorHex
        let sticky = Sticky(
            cardID: cardID,
            content: content,
            position: placement.position,
            size: placement.size,
            style: StickyTextStyle(colorHex: textColorHex, fontSize: canvas.defaultFontSize),
            fillColorHex: placement.fillColorHex,
            sortIndex: state.nextFrontCanvasIndex(forCard: cardID)
        )
        state.stickies.append(sticky)
        return state
    }

    func duplicating(id: Sticky.ID, at position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let source = state.stickies[try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")]
        let copy = Sticky(
            cardID: source.cardID,
            linkedCardID: nil,  // a duplicate is always a free sticky (see protocol note)
            content: source.content,
            position: position,
            size: source.size,
            style: source.style,
            fillColorHex: source.fillColorHex,
            sortIndex: state.nextFrontCanvasIndex(forCard: source.cardID)
        )
        state.stickies.append(copy)
        return state
    }

    func editing(id: Sticky.ID, content: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        state.stickies[idx].content = content
        return state
    }

    func settingTextColor(id: Sticky.ID, colorHex: String, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        state.stickies[idx].style.colorHex = colorHex
        return state
    }

    func settingFillColor(id: Sticky.ID, fillColorHex: String?, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        // `nil` clears the per-sticky fill so the sticky falls back to the board's free/task default.
        state.stickies[idx].fillColorHex = fillColorHex
        return state
    }

    func settingFontSize(id: Sticky.ID, fontSize: Double, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        // Re-construct through the initializer so the font size is clamped to the valid range.
        state.stickies[idx].style = StickyTextStyle(
            colorHex: state.stickies[idx].style.colorHex,
            fontSize: fontSize
        )
        return state
    }

    func settingFrame(id: Sticky.ID, to size: StickySize, at position: CanvasPosition,
                      in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        // Re-construct through the initializer so the size is clamped to the valid range. This sets
        // the sticky's full frame — an anchored resize also shifts the centre, so size and position
        // are updated in the same step (one undo entry); it is not a pure resize.
        state.stickies[idx].size = StickySize(width: size.width, height: size.height)
        state.stickies[idx].position = position
        return state
    }

    func moving(id: Sticky.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        state.stickies[idx].position = position
        return state
    }

    func togglingLabel(stickyID: Sticky.ID, labelID: UUID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: stickyID, in: \.stickies, entityKind: "Sticky")
        if let labelIdx = state.stickies[idx].labelIDs.firstIndex(of: labelID) {
            state.stickies[idx].labelIDs.remove(at: labelIdx)
        } else {
            state.stickies[idx].labelIDs.append(labelID)
        }
        return state
    }

    func bringingToFront(id: Sticky.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        let cardID = state.stickies[idx].cardID
        // Shared canvas z-order: front of *all* items (stickies + shapes), so a sticky lifts above
        // any overlapping shape too.
        state.stickies[idx].sortIndex = state.nextFrontCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func sendingToBack(id: Sticky.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let idx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        let cardID = state.stickies[idx].cardID
        state.stickies[idx].sortIndex = state.nextBackCanvasIndex(forCard: cardID, excluding: id)
        return state
    }

    func promoting(id: Sticky.ID, toColumn columnID: Column.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let stickyIdx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        let sticky = state.stickies[stickyIdx]
        // Already a task sticky: promoting again would clone a second card and orphan the first.
        // A no-op here is the same "phantom success" the stale-id throw removes, so surface it.
        guard sticky.linkedCardID == nil else {
            throw OperationError.inconsistentState(reason: "Sticky \(id) is already promoted")
        }
        // Promotion creates a new card, so it honours the same `newCardPosition` placement as
        // `CardService.adding` via the shared `BoardState` helper (also avoiding the `count`
        // gap bug that could otherwise collide a promoted card's sortIndex with an existing one).
        let newCard = Card(
            columnID: columnID,
            title: sticky.content,
            completedAt: state.resolvedCompletedAt(columnID: columnID, existing: nil, now: now()),
            createdAt: now(),
            sortIndex: state.nextCardSortIndex(inColumn: columnID)
        )
        state.cards.append(newCard)
        state.stickies[stickyIdx].linkedCardID = newCard.id
        return state
    }

    func demoting(id: Sticky.ID, in state: BoardState) throws -> BoardState {
        var state = state
        let stickyIdx = try state.requireIndex(of: id, in: \.stickies, entityKind: "Sticky")
        // Already a free sticky: there is no linked card to detach, so a no-op would report a
        // phantom success — throw rather than clear nil→nil and skip the cascade.
        guard let linkedID = state.stickies[stickyIdx].linkedCardID else {
            throw OperationError.inconsistentState(reason: "Sticky \(id) is already a free sticky")
        }
        state.stickies[stickyIdx].linkedCardID = nil
        // Demotion deletes the linked card. That card's own canvas may hold further task stickies
        // linking to grandchild cards, so cascade the whole subtree via the shared BoardState helper
        // rather than pruning one level — otherwise the grandchildren orphan in the store.
        return state.deletingCardSubtrees(rootCardIDs: [linkedID])
    }

    func deleting(id: Sticky.ID, from state: BoardState) throws -> BoardState {
        guard state.stickies.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Sticky", id: id)
        }
        var state = state
        state.stickies.removeAll { $0.id == id }
        // Cascade: a connector whose source or target is the deleted sticky has a dangling end, so
        // it is removed too.
        state.connectors.removeAll { $0.sourceStickyID == id || $0.targetStickyID == id }
        return state
    }
}
