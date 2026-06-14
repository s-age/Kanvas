import Foundation

struct BoardState: Sendable, Equatable {
    var board: Board
    var columns: [Column]
    var cards: [Card]
    var stickies: [Sticky]
    /// Drawable shapes (rectangle / ellipse / line) on cards' canvases. Share the canvas z-order
    /// space with stickies (see `nextFrontCanvasIndex`). Defaulted so snapshots predating shapes —
    /// and existing `BoardState(...)` call sites — keep compiling.
    var shapes: [CanvasShape] = []
    /// Bitmap images placed on cards' canvases. Their pixels live in sidecar asset files (keyed by
    /// `CanvasImage.imageID`); only the placement entity lives here. Share the canvas `sortIndex`
    /// z-order space with stickies/shapes (see `nextFrontCanvasIndex`). Defaulted so snapshots
    /// predating images — and existing `BoardState(...)` call sites — keep compiling.
    var images: [CanvasImage] = []
    /// Directed links between stickies on cards' canvases. Connectors do **not** join the canvas
    /// `sortIndex` z-order (they render behind every sticky/shape), so they take no part in
    /// `nextFrontCanvasIndex`. Defaulted so snapshots predating connectors — and existing
    /// `BoardState(...)` call sites — keep compiling.
    var connectors: [Connector] = []
    /// Free-text objects (background/border-less text) placed on cards' canvases. Share the canvas
    /// `sortIndex` z-order space with stickies/shapes/images (see `nextFrontCanvasIndex`). Defaulted
    /// so snapshots predating texts — and existing `BoardState(...)` call sites — keep compiling.
    var texts: [CanvasText] = []
    /// App-wide registry of shared label definitions; stickies reference these by id.
    var labels: [StickyLabel] = []
    var settings: BoardSettings = .default

    func isCompletionColumn(_ columnID: Column.ID) -> Bool {
        columns.first { $0.id == columnID }?.isCompletionColumn ?? false
    }

    /// Resolves an entity's index in one of this state's collections, throwing
    /// `OperationError.notFound(entityKind:id:)` when no element matches. The single home for the
    /// lookup-and-resolve every id-addressed gerund transform shares, so a stale id surfaces as an
    /// error instead of a silent no-op (idempotency is a virtue only for `delete`). Callers that
    /// only need an existence check discard the returned index (`_ = try requireIndex(...)`).
    func requireIndex<Element: Identifiable>(
        of id: Element.ID,
        in keyPath: KeyPath<BoardState, [Element]>,
        entityKind: String
    ) throws -> Int where Element.ID == UUID {
        guard let index = self[keyPath: keyPath].firstIndex(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: entityKind, id: id)
        }
        return index
    }

    /// Which canvas collection owns `id`, or `nil` when no canvas item matches (an already-deleted
    /// or otherwise stale id). The routing primitive for group operations: a multi-selection carries
    /// bare ids, and this resolves each to its kind so the group transform can dispatch to the right
    /// per-kind transform. Connectors are included so group-delete can route them; they never appear
    /// in a move (no geometry). Ids are unique across the canvas collections, so the first match wins.
    func canvasItemKind(of id: UUID) -> CanvasItemKind? {
        if stickies.contains(where: { $0.id == id }) { return .sticky }
        if shapes.contains(where: { $0.id == id }) { return .shape }
        if images.contains(where: { $0.id == id }) { return .image }
        if texts.contains(where: { $0.id == id }) { return .text }
        if connectors.contains(where: { $0.id == id }) { return .connector }
        return nil
    }

    /// Single source of truth for a card's status: it is **derived from the column the card sits
    /// in**, never stored on the card. The completion column reads `.done`, the leftmost column
    /// (lowest `sortIndex`) reads `.todo`, and every column in between reads `.inProgress`. Every
    /// move — drag-and-drop or MCP — changes `columnID`, so the status follows for free and can
    /// never go stale. An unknown column id falls back to `.todo` (cannot happen under the
    /// card→column invariant; the fallback only keeps the function total).
    func status(forColumn columnID: Column.ID) -> CardStatus {
        guard columns.contains(where: { $0.id == columnID }) else { return .todo }
        if isCompletionColumn(columnID) { return .done }
        let leftmost = columns.min { $0.sortIndex < $1.sortIndex }
        return leftmost?.id == columnID ? .todo : .inProgress
    }

    /// The human-readable status: the title of the column a card sits in. Shares the same
    /// `columnID` projection home as `status(forColumn:)` so the two never drift. Empty string for
    /// an unknown column id (cannot happen under the card→column invariant).
    func columnTitle(forColumn columnID: Column.ID) -> String {
        columns.first { $0.id == columnID }?.title ?? ""
    }

    /// One above the frontmost canvas item (sticky **or** shape) in `cardID`'s canvas — the shared
    /// z-order numbering both `StickyService` and `ShapeService` adopt so the two interleave.
    /// Returns 0 when the canvas holds no other items. `excluding` drops one item (used when
    /// re-stacking an item that is already on the canvas).
    func nextFrontCanvasIndex(forCard cardID: Card.ID, excluding excludedID: UUID? = nil) -> Int {
        guard let maxIndex = canvasSortIndexes(forCard: cardID, excluding: excludedID).max() else { return 0 }
        return maxIndex + 1
    }

    /// One below the backmost canvas item (sticky **or** shape) in `cardID`'s canvas. The
    /// back-half counterpart of `nextFrontCanvasIndex`.
    func nextBackCanvasIndex(forCard cardID: Card.ID, excluding excludedID: UUID? = nil) -> Int {
        guard let minIndex = canvasSortIndexes(forCard: cardID, excluding: excludedID).min() else { return 0 }
        return minIndex - 1
    }

    /// `sortIndex`es of every canvas item (stickies + shapes + images + texts) on `cardID`'s canvas,
    /// minus `excludedID`. Backing for the front/back numbering above.
    private func canvasSortIndexes(forCard cardID: Card.ID, excluding excludedID: UUID?) -> [Int] {
        let stickyIndexes = stickies
            .filter { $0.cardID == cardID && $0.id != excludedID }
            .map(\.sortIndex)
        let shapeIndexes = shapes
            .filter { $0.cardID == cardID && $0.id != excludedID }
            .map(\.sortIndex)
        let imageIndexes = images
            .filter { $0.cardID == cardID && $0.id != excludedID }
            .map(\.sortIndex)
        let textIndexes = texts
            .filter { $0.cardID == cardID && $0.id != excludedID }
            .map(\.sortIndex)
        return stickyIndexes + shapeIndexes + imageIndexes + textIndexes
    }

    /// Single source of truth for the `completedAt` invariant: when auto-complete is on, a
    /// card's `completedAt` is non-nil **iff** it sits in the board's completion column —
    /// existing timestamps are preserved and `now` stamps a newly-completed card. When the
    /// `autoCompleteOnMove` setting is off, the timestamp is left untouched (the user manages
    /// completion manually), so neither a move into nor out of the completion column changes it.
    /// Every site that creates a card or changes its column / the completion flag routes through this.
    func resolvedCompletedAt(columnID: Column.ID, existing: Date?, now: Date) -> Date? {
        guard settings.board.autoCompleteOnMove else { return existing }
        return isCompletionColumn(columnID) ? (existing ?? now) : nil
    }

    /// The `sortIndex` a newly-created card should take in `columnID`, honouring the board's
    /// `newCardPosition` setting. Single source of truth shared by every card-creating path
    /// (`CardService.adding`, `StickyService.promoting`) so placement stays consistent.
    /// Strict (`min - 1` / `max + 1`) rather than `count`: `moving` does not recompact the source
    /// column, so a column may carry gaps or indices ≥ its card count — strict bounds guarantee the
    /// intended end even then.
    func nextCardSortIndex(inColumn columnID: Column.ID) -> Int {
        let sortIndexes = cards.filter { $0.columnID == columnID }.map(\.sortIndex)
        switch settings.board.newCardPosition {
        case .top:
            return (sortIndexes.min() ?? 0) - 1
        case .bottom:
            return (sortIndexes.max() ?? -1) + 1
        }
    }

    /// Recursively deletes `rootCardIDs` together with their whole drill-down subtree, returning the
    /// pruned state. The drill-down model nests cards: a card's canvas may hold *task* stickies
    /// (`linkedCardID != nil`) that link to sub-cards, whose canvases may in turn link to further
    /// sub-cards. Removing only the direct children of `rootCardIDs` would strand those nested
    /// cards — and every sticky / shape / image / text / connector on their canvases — as unreachable
    /// orphans in the whole-blob store. So the closure is computed transitively: starting from the
    /// roots, every still-live task sticky `cardID`-owned by a doomed card contributes its
    /// `linkedCardID` to the doomed set, until no new card is reached.
    ///
    /// The single home for the cascade shared by `CardService.deleting`, `ColumnService.deleting`,
    /// and `StickyService.demoting` so the three can never drift on how deep they prune. Image asset
    /// *files* are intentionally left on disk for undo-safety (a future GC sweeps orphans); only the
    /// placement entities are removed here (see `CardService.deleting`).
    func deletingCardSubtrees(rootCardIDs: Set<Card.ID>) -> BoardState {
        var doomed = rootCardIDs
        var frontier = rootCardIDs
        while !frontier.isEmpty {
            let nextLinked = stickies
                .filter { frontier.contains($0.cardID) }
                .compactMap(\.linkedCardID)
                .filter { !doomed.contains($0) }
            if nextLinked.isEmpty { break }
            let newlyReached = Set(nextLinked)
            doomed.formUnion(newlyReached)
            frontier = newlyReached
        }

        var state = self
        state.stickies.removeAll { doomed.contains($0.cardID) }
        // A *task* sticky may live on a still-live (parent) canvas yet link into the doomed subtree;
        // prune it too. Capture its id so its connectors on that parent canvas — which the
        // by-cardID connector sweep below cannot reach — are dropped by endpoint, mirroring
        // `StickyService.deleting` (a connector with a dangling end is removed).
        var prunedLinkingStickyIDs: Set<Sticky.ID> = []
        state.stickies.removeAll { sticky in
            guard sticky.linkedCardID.map({ doomed.contains($0) }) ?? false else { return false }
            prunedLinkingStickyIDs.insert(sticky.id)
            return true
        }
        state.shapes.removeAll { doomed.contains($0.cardID) }
        state.images.removeAll { doomed.contains($0.cardID) }
        state.texts.removeAll { doomed.contains($0.cardID) }
        state.connectors.removeAll {
            doomed.contains($0.cardID)
                || prunedLinkingStickyIDs.contains($0.sourceStickyID)
                || prunedLinkingStickyIDs.contains($0.targetStickyID)
        }
        state.cards.removeAll { doomed.contains($0.id) }
        return state
    }

    static func empty(title: String = "Board") -> BoardState {
        let board = Board(title: title)
        return BoardState(board: board, columns: [], cards: [], stickies: [])
    }

    static func withDefaultColumns(title: String = "Board") -> BoardState {
        from(template: .default, title: title)
    }

    /// Instantiates a fresh board from the Default template: copies the template settings and
    /// materialises each `TemplateColumn` into a `Column` with a new `boardID` and a new column id
    /// (title / sortIndex / completion flag / colours carried over). Editing the template later
    /// never reaches back into a board minted this way.
    static func from(template: BoardTemplate, title: String = "Board") -> BoardState {
        let board = Board(title: title)
        let columns = template.columns
            .sorted { $0.sortIndex < $1.sortIndex }
            .enumerated()
            .map { index, seed in
                Column(
                    boardID: board.id,
                    title: seed.title,
                    sortIndex: index,
                    isCompletionColumn: seed.isCompletionColumn,
                    headerColorHex: seed.headerColorHex,
                    headerTextColorHex: seed.headerTextColorHex,
                    bodyColorHex: seed.bodyColorHex,
                    indicatorColorHex: seed.indicatorColorHex
                )
            }
        return BoardState(board: board, columns: columns, cards: [], stickies: [], settings: template.settings)
    }
}
