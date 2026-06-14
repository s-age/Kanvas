import Foundation

// The Domain Services layer's protocol surface, consolidated into one file per layer.

/// Owns the board-level operations that have no per-entity Service: the board catalog (create /
/// switch / rename / delete), the active board's load + bootstrap, the per-process undo ring, the
/// Default template, and the multi-field board-settings save. "Which board becomes active next"
/// and "the last board may not be deleted" are domain rules that live behind this Service.
///
/// Like the entity Services, the imperative verbs own the `repository.mutate` / direct-dispatch
/// boundary; reads are plain pass-throughs. `editBoardSettings` composes `ColumnService`'s pure
/// transforms inside one `mutateBoard` (see `BoardManagementService`).
///
/// The imperative verbs + reads are `async`: the Repository's `flock` + JSON I/O runs off the
/// cooperative pool (see `BoardRepository`), so every call that reaches the store suspends rather
/// than blocking a pool thread. The pure `deletingBoard` transform (no I/O) stays synchronous.
protocol BoardManagementServiceProtocol: Sendable {
    // MARK: Reads

    /// The active board's full state. Throws `OperationError.loadFailed` when no catalog exists yet
    /// — callers that must establish one use `bootstrapActiveBoard()` instead.
    func loadActiveBoard() async throws -> BoardState
    /// The set of active-board card ids matching `query` — case-insensitive substring across each
    /// card's title / Markdown body / sticky text / own UUID, OR-combined. A blank query returns
    /// every card id (no filter). Read-only, in-memory over the loaded `BoardState` (ticket 59B10FBA).
    func matchingCardIDs(query: String) async throws -> Set<UUID>
    /// The same match as `matchingCardIDs(query:)` but over an **already-loaded** `BoardState`, so a
    /// caller that just read the board (e.g. the combined `bootstrapActiveBoardWithCatalog` snapshot)
    /// can run the active filter without a second store read (PR #123 r2-1). Pure + synchronous — no
    /// I/O, no lock — the match rule lives in one place (`CardQuery`) for both entry points.
    func matchingCardIDs(in state: BoardState, query: String) -> Set<UUID>
    /// The active board, establishing one when it can't be loaded (missing **or** corrupt
    /// `catalog.json`). Tries in priority order: migrate a legacy single-board file, else rebuild
    /// the catalog from surviving `boards/*.json` (so a lost/corrupt index never orphans existing
    /// boards), else seed a board from the Default template. Each path sets the active board.
    func bootstrapActiveBoard() async throws -> BoardState
    /// Like `bootstrapActiveBoard`, but also returns the board catalog (list + active id) from the
    /// **same** single store read, so a refresh derives the board, the open card's detail, and the
    /// picker list from one flock + decode instead of three (ticket 8DCB811D). Applies the identical
    /// bootstrap recovery (migrate legacy / recover orphans / seed default) on a missing/corrupt
    /// catalog.
    func bootstrapActiveBoardWithCatalog() async throws -> ActiveBoardSnapshot
    /// Any board's full state by id, without switching the active board.
    func loadBoard(id: Board.ID) async throws -> BoardState
    /// The board catalog — every board (id + title) in display order plus the active id — read under
    /// one lock.
    func listBoards() async throws -> BoardCatalog
    /// The app-level Default template (settings + column blueprint copied into every new board).
    func loadTemplate() async throws -> BoardTemplate

    // MARK: Mutations

    /// Creates a board from the Default template, makes it active, and returns it.
    func addBoard(title: String) async throws -> BoardState
    /// Pure transform backing `addBoard` / bootstrap seeding / legacy migration: registers `board`
    /// into the catalog (idempotent on its id) and makes it the active board. The Repository applies
    /// this inside its cross-process lock; it owns the "new board joins the index and becomes active"
    /// rule (the create-side mirror of `deletingBoard`).
    func registeringBoard(_ board: Board, into catalog: BoardCatalog) -> BoardCatalog
    /// Pure transform backing `recoverOrphanedBoards`: picks which recovered board becomes active
    /// when a lost catalog is rebuilt — keeps the prior active board when its snapshot survived
    /// (the Repository pre-sets `activeBoardID` to it, else `nil`), otherwise promotes the first
    /// recovered board. The Repository applies this inside its cross-process lock; it owns the
    /// "which board is active" rule on the recovery path (sibling of `deletingBoard` /
    /// `registeringBoard`, the 62FDA087 family).
    func recoveringActiveBoard(in catalog: BoardCatalog) -> BoardCatalog
    /// Switches the active board, returning the target's state. Resets the undo history.
    func switchBoard(to id: Board.ID) async throws -> BoardState
    /// Renames a board (any board), returning the updated catalog. Never changes which is active.
    func renameBoard(id: Board.ID, title: String) async throws -> (boards: [Board], activeBoardID: UUID?)
    /// Deletes a board and returns the resulting active board's state.
    func deleteBoard(id: Board.ID) async throws -> BoardState
    /// Pure transform backing `deleteBoard`: removes `id` from the catalog, promotes the first
    /// remaining board to active when the deleted one was active, and throws
    /// `OperationError.inconsistentState` when it would delete the last board. The Repository applies
    /// this inside its cross-process lock; it owns the "next active" / "last board protected" rules.
    func deletingBoard(id: Board.ID, from catalog: BoardCatalog) throws -> BoardCatalog
    /// Restores the most recent pre-mutation snapshot of the active board, returning an
    /// `UndoOutcome`: `.restored` (reverted), `.nothingToUndo` (empty ring), or
    /// `.abortedExternalEdit` (a foreign writer — MCP — edited the board since that mutation, so
    /// undo refuses to clobber the intervening edit). See `BoardRepositoryProtocol.undo()`.
    func undo() async throws -> UndoOutcome
    /// Persists the Default template. Never touches existing boards — it only shapes future ones.
    func saveTemplate(_ template: BoardTemplate) async throws
    /// Applies a board's settings and its columns' colours / completion flag in one mutation.
    func editBoardSettings(boardID: Board.ID, settings: BoardSettings,
                             columns: [ColumnAppearanceUpdate]) async throws -> BoardState
    /// Applies **one** column's keep/clear/set colours + completion flag on the active board,
    /// resolved inside a single `mutate` against the column reloaded under the store lock — so the
    /// edit is one atomic read-modify-write with no lost-update window for sibling columns (ticket
    /// 620B3601).
    func editColumnAppearance(columnID: Column.ID,
                              edit: ColumnAppearanceFields) async throws -> BoardState
}

/// Service for canvas images. The imperative verbs own the `repository.mutate` boundary; the pure
/// transforms are the composable core (every transform computes the new `BoardState` and returns
/// it). Images share the canvas `sortIndex` z-order with stickies and shapes, so `adding` /
/// `bringingToFront` / `sendingToBack` number against `BoardState.nextFrontCanvasIndex`.
///
/// The image's pixel bytes are persisted out-of-band (sidecar asset keyed by `assetID`); this
/// service owns both those bytes (`add` / `loadImageData`) and the `CanvasImage` placement entity.
/// Resizing preserves the source aspect ratio.
protocol CanvasImageServiceProtocol: Sendable {
    // MARK: Imperative verbs — own the `repository.mutate` boundary (Shape 1). `add` also persists
    // the image's pixel bytes; `loadImageData` reads them. `async`: the asset + board I/O runs off
    // the cooperative pool (see `ImageAssetStoreProtocol` / `BoardRepository`).

    /// Saves the image bytes then places a `CanvasImage` on the card's canvas (bytes first, so a
    /// failed mutation can only orphan an asset file, never reference missing pixels).
    func add(imageData: Data, naturalSize: NaturalSize,
             position: CanvasPosition, toCardCanvas cardID: Card.ID) async throws -> BoardState
    func move(id: CanvasImage.ID, to position: CanvasPosition) async throws -> BoardState
    func resize(id: CanvasImage.ID, to placement: ImagePlacement) async throws -> BoardState
    func bringToFront(id: CanvasImage.ID) async throws -> BoardState
    func sendToBack(id: CanvasImage.ID) async throws -> BoardState
    func delete(id: CanvasImage.ID) async throws -> BoardState
    /// Persists image bytes as a standalone sidecar asset and returns its id, **without** placing a
    /// `CanvasImage` or mutating any board (so no undo entry). Used by the Markdown editor's
    /// drag-drop import: the id is referenced from the card body as `kanvas-asset://<id>` text, kept
    /// reachable by the GC's Markdown scan. Shares the same bytes-first asset store as `add`.
    func saveAsset(imageData: Data) async throws -> UUID
    /// Reads an image asset's pixel bytes for display.
    func loadImageData(assetID: UUID) async throws -> Data

    /// Deletes a Markdown inline image from a card: removes the **first** `kanvas-asset://<assetID>`
    /// reference from the card's body, then reclaims the asset bytes **iff** no card/Canvas placement
    /// on any board still references that id (a refcount — bytes go only on the last reference). The
    /// body rewrite persists inside `mutate`; the cross-board reachability check + bytes delete run
    /// after (async I/O, outside the lock). Throws `notFound` when the card or the reference is absent.
    func deleteMarkdownImage(cardID: Card.ID, assetID: UUID) async throws -> BoardState

    /// Best-effort sweep of orphaned sidecar assets: deletes every stored asset file that **no**
    /// `CanvasImage` on **any** board references. Reachability is computed across the whole catalog
    /// and the sweep aborts (deletes nothing) if any board fails to load, so a partial read can
    /// never reclaim a still-referenced asset. A grace period (`AssetGCPolicy`) excludes recently
    /// written files, so an in-flight cross-process `add` is never swept. Intended to run once at
    /// startup, when the per-process undo ring is empty — so it cannot strip an asset an undo would
    /// restore. Performs blocking I/O (reads every board snapshot + scans the assets directory),
    /// which is offloaded to dedicated queues so it never parks a cooperative-pool thread.
    ///
    /// Best-effort with no result channel, so its outcome is reported through the injected
    /// diagnostics port instead of a return value: the reclaimed count, any per-file delete failure,
    /// and — critically — the reachability abort (a permanently unreadable board makes the sweep
    /// reclaim nothing forever, which must not stay silent). Still `throws` the abort so the caller's
    /// existing best-effort `try?` is unchanged.
    func sweepOrphanedAssets() async throws

    // MARK: Pure transforms — composable, side-effect-free core.

    func adding(asset: ImageAssetRef, placement: ImagePlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState
    func moving(id: CanvasImage.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState
    /// Resize an image: the new box + shifted centre (`placement`) commit together. The height is
    /// re-derived from the new width and the image's stored `aspectRatio`, so the image never
    /// distorts regardless of the box the canvas feeds in.
    func resizing(id: CanvasImage.ID, to placement: ImagePlacement, in state: BoardState) throws -> BoardState
    func bringingToFront(id: CanvasImage.ID, in state: BoardState) throws -> BoardState
    func sendingToBack(id: CanvasImage.ID, in state: BoardState) throws -> BoardState
    func deleting(id: CanvasImage.ID, from state: BoardState) throws -> BoardState

    /// Pure: removes the first `kanvas-asset://<assetID>` reference from the card's `markdownContent`.
    /// Throws `notFound` when the card is absent or carries no reference to that id. The bytes reclaim
    /// happens in the imperative `deleteMarkdownImage` verb (after persistence); this only edits text.
    func removingMarkdownReference(to assetID: UUID, fromCard cardID: Card.ID,
                                   in state: BoardState) throws -> BoardState

    /// Fits a source pixel size into `ImageSize.defaultMaxSide` preserving aspect ratio, returning
    /// both the initial on-canvas size **and** the source aspect ratio — the single place those
    /// two derive from the natural dimensions, so the `CanvasImage`'s size and `aspectRatio` cannot
    /// drift. Pure helper (no state).
    func fittedImage(naturalSize: NaturalSize) -> (size: ImageSize, aspectRatio: Double)
}

/// Group operations over a multi-selection of canvas items (stickies / shapes / images /
/// connectors). Composes the sibling services' **pure** transforms inside ONE `repository.mutate`,
/// so a whole marquee move or delete lands as a single undo entry and a single cross-process
/// `flock` + read-modify-write — not the N of looping a per-item imperative verb, which also
/// overflowed the depth-5 undo ring on a large selection (ticket 4FF14DCF). This is a sanctioned
/// multi-entity composition (see `arch-domain-services.md` → "Multi-entity composition"): only the
/// siblings' pure transforms are reused, never their imperative verbs (each of those would open a
/// second `mutate`). Routing by id→kind is `BoardState.canvasItemKind(of:)`.
protocol CanvasGroupServiceProtocol: Sendable {
    // MARK: Imperative verbs — own the single `repository.mutate` boundary. `async` (offloaded I/O).

    /// Moves every item to its new position, routing each id by kind. Connectors carry no geometry
    /// and are ignored. A movement whose id no longer matches any canvas item is skipped — the whole
    /// batch is one atomic mutation, so a vanished item (a concurrent delete landed between the
    /// gesture and the commit) drops out rather than aborting the others.
    func moveGroup(_ movements: [CanvasItemMovement]) async throws -> BoardState
    /// Deletes every id, routing by kind and tolerating an already-absent id (mirrors the per-item
    /// delete's `notFound` skip). A sticky delete cascades its connectors, so a connector also named
    /// later in the same batch is then a no-op. One mutation, one undo entry.
    func deleteGroup(ids: [UUID]) async throws -> BoardState

    // MARK: Pure transforms — composable, side-effect-free core (unit-tested directly).

    func movingGroup(_ movements: [CanvasItemMovement], in state: BoardState) throws -> BoardState
    func deletingGroup(ids: [UUID], in state: BoardState) throws -> BoardState
}

protocol CardServiceProtocol: Sendable {
    // MARK: Imperative verbs — own the `repository.mutate` boundary (Shape 1). These are what the
    // UseCase calls; each loads + persists the active board, applying the matching pure transform.
    // `async`: the Repository's `flock` + JSON I/O runs off the cooperative pool.

    /// Appends a new card built from `seed` (caller-supplied id + title + optional Markdown —
    /// see `CardSeed`) to the given column, persisting the change.
    func add(_ seed: CardSeed, columnID: Column.ID) async throws -> BoardState
    func edit(id: Card.ID, fields: EditCardFields) async throws -> BoardState
    func move(id: Card.ID, toColumn: Column.ID, before: Card.ID?) async throws -> BoardState
    func delete(id: Card.ID) async throws -> BoardState

    // MARK: Pure transforms — the composable, side-effect-free core. Unit-tested directly and
    // reused by sibling services that need a multi-entity transform inside one mutate.

    func adding(_ seed: CardSeed, columnID: Column.ID, to state: BoardState) -> BoardState
    func editing(id: Card.ID, fields: EditCardFields, in state: BoardState) throws -> BoardState
    func moving(id: Card.ID, toColumn: Column.ID, before: Card.ID?, in state: BoardState) throws -> BoardState
    func deleting(id: Card.ID, from state: BoardState) throws -> BoardState
}

protocol ColumnServiceProtocol: Sendable {
    // Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).
    func add(title: String) async throws -> BoardState
    func rename(id: Column.ID, to title: String) async throws -> BoardState
    func setCompletion(id: Column.ID, isCompletion: Bool) async throws -> BoardState
    func reorder(id: Column.ID, before anchorID: Column.ID?) async throws -> BoardState
    func delete(id: Column.ID) async throws -> BoardState

    // Pure transforms — composable, side-effect-free core.
    func adding(title: String, boardID: Board.ID, to state: BoardState) -> BoardState
    func renaming(id: Column.ID, to title: String, in state: BoardState) throws -> BoardState
    func settingCompletion(id: Column.ID, isCompletion: Bool, in state: BoardState) throws -> BoardState
    func settingColors(id: Column.ID, colors: ColumnColors, in state: BoardState) throws -> BoardState
    func reordering(id: Column.ID, before anchorID: Column.ID?, in state: BoardState) throws -> BoardState
    func deleting(id: Column.ID, from state: BoardState) throws -> BoardState
}

/// Service for canvas connectors (directed sticky→sticky links). Connectors carry no geometry and
/// take no part in the canvas `sortIndex` z-order, so there is no front/back numbering here. The
/// imperative verbs own the `repository.mutate` boundary; the pure transforms are the composable
/// core (also reused by `add` for the create-target-sticky path).
protocol ConnectorServiceProtocol: Sendable {
    // MARK: Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).

    /// Adds a connector, optionally creating the target sticky (when `seed.existingTargetStickyID` is
    /// nil) in the same mutation so the gesture is one undo step. `seed.strokeColorHex` is the explicit
    /// stroke colour the caller chose, or `nil` to inherit the canvas-contrasting default (see
    /// `adding`).
    func add(cardID: Card.ID, seed: ConnectorSeed) async throws -> BoardState
    func setCap(id: Connector.ID, cap: ConnectorEndpointCap) async throws -> BoardState
    func setRouting(id: Connector.ID, routing: ConnectorRouting) async throws -> BoardState
    /// `colorHex` is an explicit stroke colour, or `nil` to clear back to **unset** (adaptive at
    /// draw time) — mirroring `StickyService.setFillColor`'s clearable fill.
    func setStrokeColor(id: Connector.ID, colorHex: String?) async throws -> BoardState
    func setStrokeWidth(id: Connector.ID, width: Double) async throws -> BoardState
    /// Sets (or clears, with `nil`) a connector's waypoint offset — the central deformation handle's
    /// shift from the midpoint of the two endpoint edge midpoints (`nil` ⇒ automatic route).
    func setWaypoint(id: Connector.ID, offset: CanvasOffset?) async throws -> BoardState
    /// Applies any subset of cap / routing / stroke colour / stroke width in one mutation.
    func setStyle(id: Connector.ID, change: ConnectorStyleChange) async throws -> BoardState
    /// Re-attaches a connector's endpoint(s). A `nil` side is left untouched; a provided side moves
    /// that end to its new sticky + edge (the same sticky with a new edge is a plain edge change).
    /// Bundles both sides like `setStyle` so the self-loop rule (the reconnected
    /// `sourceStickyID == targetStickyID` is rejected) is validated once before the single write.
    func reconnect(id: Connector.ID,
                   source: ConnectorEndpoint?, target: ConnectorEndpoint?) async throws -> BoardState
    func delete(id: Connector.ID) async throws -> BoardState

    // MARK: Pure transforms — composable, side-effect-free core.

    /// Pure core of `add`. Rejects a self-loop (`sourceStickyID == targetStickyID` ⇒
    /// `ValidationError.connectorSelfLoop`) before appending, so the rule matches `reconnecting`'s.
    /// The UI grow gesture avoids self-loops structurally; this guard is the backstop for the MCP
    /// `canvas_connector_add` path, which previously appended a self-linking connector unchecked.
    func adding(endpoints: ConnectorEndpoints, strokeColorHex: String?,
                toCardCanvas cardID: Card.ID, in state: BoardState) throws -> BoardState
    func settingCap(id: Connector.ID, cap: ConnectorEndpointCap, in state: BoardState) throws -> BoardState
    func settingRouting(id: Connector.ID, routing: ConnectorRouting, in state: BoardState) throws -> BoardState
    func settingStrokeColor(id: Connector.ID, colorHex: String?, in state: BoardState) throws -> BoardState
    func settingStrokeWidth(id: Connector.ID, width: Double, in state: BoardState) throws -> BoardState
    /// Pure core of `setWaypoint`. Resolves the connector (`OperationError.notFound` if absent) and
    /// writes (or clears) its waypoint offset.
    func settingWaypoint(id: Connector.ID, offset: CanvasOffset?, in state: BoardState) throws -> BoardState
    /// Pure core of `reconnect`. Resolves the connector (`OperationError.notFound` if absent),
    /// validates each provided side's new sticky exists on the connector's card
    /// (`OperationError.notFound` if absent), rejects a resulting self-loop
    /// (`ValidationError.connectorSelfLoop`), then rewrites the touched endpoint field(s).
    func reconnecting(id: Connector.ID, source: ConnectorEndpoint?, target: ConnectorEndpoint?,
                      in state: BoardState) throws -> BoardState
    func deleting(id: Connector.ID, from state: BoardState) throws -> BoardState
}

/// Service for the app-wide `StickyLabel` registry (`BoardState.labels`). The imperative verbs own
/// the `repository.mutate` boundary (Shape 1); the pure transforms are the composable,
/// side-effect-free core (each computes and returns a new `BoardState` without persisting).
protocol LabelServiceProtocol: Sendable {
    // Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).
    func add(name: String, colorHex: String) async throws -> BoardState
    func edit(id: UUID, name: String, colorHex: String) async throws -> BoardState
    func delete(id: UUID) async throws -> BoardState

    // Pure transforms — composable, side-effect-free core.
    func adding(name: String, colorHex: String, in state: BoardState) -> BoardState
    func editing(id: UUID, name: String, colorHex: String, in state: BoardState) throws -> BoardState
    /// Removes the label from the registry **and** from every sticky's `labelIDs`.
    func deleting(id: UUID, from state: BoardState) throws -> BoardState
}

/// Service for the durable Markdown autosave journal (ticket 44C9D3C2). Shape 1 (imperative verbs,
/// holds the journal repository), but the journal is a **separate substrate** from the board store
/// — no `repository.mutate`, no `flock`, no undo — so it has no pure gerund transforms. `async`:
/// the journal's file I/O is offloaded off the cooperative pool (see `MarkdownJournalStoreProtocol`).
protocol MarkdownJournalServiceProtocol: Sendable {
    /// Persists (or overwrites) a card's latest unsaved Markdown text, stamped `enqueuedAt`.
    func record(cardID: UUID, content: String, at enqueuedAt: Date) async throws
    /// Every journaled pending edit — the startup-restore candidate set. Named `listAll()` to match
    /// the Repository method it backs (arch naming rule: shared read verb across the hop).
    func listAll() async throws -> [PendingMarkdownEdit]
    /// Removes a card's journal entry once its write lands (or the user discards it).
    func clear(cardID: UUID) async throws
}

/// Service for canvas shapes. Mirrors `StickyServiceProtocol`: the imperative verbs own the
/// `repository.mutate` boundary (Shape 1); the pure transforms compute and return a new `BoardState`
/// without persisting. Shapes share the canvas `sortIndex` z-order with stickies, so `adding` /
/// `bringingToFront` / `sendingToBack` number against `BoardState.nextFrontCanvasIndex`.
protocol ShapeServiceProtocol: Sendable {
    // Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).
    func add(spec: ShapeSpec, placement: ShapePlacement,
             toCardCanvas cardID: Card.ID) async throws -> BoardState
    func move(id: CanvasShape.ID, to position: CanvasPosition) async throws -> BoardState
    func resize(id: CanvasShape.ID, to placement: ShapePlacement, lineRising: Bool?) async throws -> BoardState
    func setStrokeColor(id: CanvasShape.ID, colorHex: String) async throws -> BoardState
    func setFillColor(id: CanvasShape.ID, colorHex: String?) async throws -> BoardState
    func setStrokeWidth(id: CanvasShape.ID, width: Double) async throws -> BoardState
    func bringToFront(id: CanvasShape.ID) async throws -> BoardState
    func sendToBack(id: CanvasShape.ID) async throws -> BoardState
    func delete(id: CanvasShape.ID) async throws -> BoardState

    // Pure transforms — composable, side-effect-free core.
    /// `spec` carries the open visual `kind` token plus the behaviour-class `topology` chosen by the
    /// registry at creation and persisted on the shape.
    func adding(spec: ShapeSpec, placement: ShapePlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState
    func moving(id: CanvasShape.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState
    /// Resize/reshape. The clamp rule is selected by the shape's stored `topology`
    /// (`.segment` → min-length; `.box` → `minFilledSide`). `lineRising` is recorded only for a
    /// `.segment` endpoint drag; pass `nil` for box resizes / to leave orientation unchanged.
    func resizing(id: CanvasShape.ID, to placement: ShapePlacement,
                  lineRising: Bool?, in state: BoardState) throws -> BoardState
    func settingStrokeColor(id: CanvasShape.ID, colorHex: String, in state: BoardState) throws -> BoardState
    /// `colorHex == nil` sets **no fill** (stroke-only); any value sets a literal fill colour.
    func settingFillColor(id: CanvasShape.ID, colorHex: String?, in state: BoardState) throws -> BoardState
    func settingStrokeWidth(id: CanvasShape.ID, width: Double, in state: BoardState) throws -> BoardState
    func bringingToFront(id: CanvasShape.ID, in state: BoardState) throws -> BoardState
    func sendingToBack(id: CanvasShape.ID, in state: BoardState) throws -> BoardState
    func deleting(id: CanvasShape.ID, from state: BoardState) throws -> BoardState
}

/// Service for canvas free-text objects (background/border-less text). Mirrors `ShapeServiceProtocol`:
/// the imperative verbs own the `repository.mutate` boundary (Shape 1); the pure transforms compute
/// and return a new `BoardState` without persisting. Texts share the canvas `sortIndex` z-order with
/// stickies/shapes/images, so `adding` / `bringingToFront` / `sendingToBack` number against
/// `BoardState.nextFrontCanvasIndex`. Unlike stickies, texts carry no `linkedCardID` (no
/// promote/demote), no labels, and no connector attachment.
protocol TextServiceProtocol: Sendable {
    // Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).
    func add(content: String, placement: TextPlacement, toCardCanvas cardID: Card.ID) async throws -> BoardState
    func duplicate(id: CanvasText.ID, at position: CanvasPosition) async throws -> BoardState
    func edit(id: CanvasText.ID, content: String) async throws -> BoardState
    func move(id: CanvasText.ID, to position: CanvasPosition) async throws -> BoardState
    func resize(id: CanvasText.ID, to placement: TextPlacement) async throws -> BoardState
    func setColor(id: CanvasText.ID, colorHex: String) async throws -> BoardState
    func setFontSize(id: CanvasText.ID, fontSize: Double) async throws -> BoardState
    func bringToFront(id: CanvasText.ID) async throws -> BoardState
    func sendToBack(id: CanvasText.ID) async throws -> BoardState
    func delete(id: CanvasText.ID) async throws -> BoardState

    // Pure transforms — composable, side-effect-free core.
    func adding(content: String, placement: TextPlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState
    func duplicating(id: CanvasText.ID, at position: CanvasPosition, in state: BoardState) throws -> BoardState
    /// Commits an edit; an empty body (trimmed) auto-deletes the text object (no blank text on the
    /// canvas — ticket 7C1D6316 決め事 2).
    func editing(id: CanvasText.ID, content: String, in state: BoardState) throws -> BoardState
    func moving(id: CanvasText.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState
    func resizing(id: CanvasText.ID, to placement: TextPlacement, in state: BoardState) throws -> BoardState
    func settingColor(id: CanvasText.ID, colorHex: String, in state: BoardState) throws -> BoardState
    func settingFontSize(id: CanvasText.ID, fontSize: Double, in state: BoardState) throws -> BoardState
    func bringingToFront(id: CanvasText.ID, in state: BoardState) throws -> BoardState
    func sendingToBack(id: CanvasText.ID, in state: BoardState) throws -> BoardState
    func deleting(id: CanvasText.ID, from state: BoardState) throws -> BoardState
}

protocol StickyServiceProtocol: Sendable {
    // Imperative verbs — own the `repository.mutate` boundary (Shape 1). `async` (offloaded I/O).
    func add(content: String, placement: StickyPlacement, toCardCanvas cardID: Card.ID) async throws -> BoardState
    func duplicate(id: Sticky.ID, at position: CanvasPosition) async throws -> BoardState
    func edit(id: Sticky.ID, content: String) async throws -> BoardState
    func setTextColor(id: Sticky.ID, colorHex: String) async throws -> BoardState
    func setFillColor(id: Sticky.ID, fillColorHex: String?) async throws -> BoardState
    func setFontSize(id: Sticky.ID, fontSize: Double) async throws -> BoardState
    /// Sets the sticky's full frame — size **and** centre — committed together as one mutation /
    /// one undo entry. An anchored (corner-fixed) resize moves the centre as the size changes, so
    /// this is not a pure resize; use `move` to set only the centre.
    func setFrame(id: Sticky.ID, to size: StickySize, at position: CanvasPosition) async throws -> BoardState
    func move(id: Sticky.ID, to position: CanvasPosition) async throws -> BoardState
    func toggleLabel(stickyID: Sticky.ID, labelID: UUID) async throws -> BoardState
    func bringToFront(id: Sticky.ID) async throws -> BoardState
    func sendToBack(id: Sticky.ID) async throws -> BoardState
    func promote(id: Sticky.ID, toColumn columnID: Column.ID) async throws -> BoardState
    func demote(id: Sticky.ID) async throws -> BoardState
    func delete(id: Sticky.ID) async throws -> BoardState

    // Pure transforms — composable, side-effect-free core.
    func adding(content: String, placement: StickyPlacement,
                toCardCanvas cardID: Card.ID, in state: BoardState) -> BoardState
    /// Clones the sticky at `id` onto the same card's canvas at `position`. The copy is always a
    /// free sticky (`linkedCardID` cleared) so a duplicate never points a second sticky at the
    /// source's linked card. Content / size / style carry over; sort order goes to the front.
    func duplicating(id: Sticky.ID, at position: CanvasPosition, in state: BoardState) throws -> BoardState
    func editing(id: Sticky.ID, content: String, in state: BoardState) throws -> BoardState
    func settingTextColor(id: Sticky.ID, colorHex: String, in state: BoardState) throws -> BoardState
    /// Sets the per-sticky background fill ("RRGGBB"), or `nil` to clear it back to the board's
    /// free/task default fill.
    func settingFillColor(id: Sticky.ID, fillColorHex: String?, in state: BoardState) throws -> BoardState
    func settingFontSize(id: Sticky.ID, fontSize: Double, in state: BoardState) throws -> BoardState
    func settingFrame(id: Sticky.ID, to size: StickySize, at position: CanvasPosition,
                      in state: BoardState) throws -> BoardState
    func moving(id: Sticky.ID, to position: CanvasPosition, in state: BoardState) throws -> BoardState
    /// Toggles the shared label `labelID` on the sticky `stickyID`: removes it when already
    /// tagged, otherwise appends it. Throws `OperationError.notFound` when the sticky is absent.
    func togglingLabel(stickyID: Sticky.ID, labelID: UUID, in state: BoardState) throws -> BoardState
    func bringingToFront(id: Sticky.ID, in state: BoardState) throws -> BoardState
    func sendingToBack(id: Sticky.ID, in state: BoardState) throws -> BoardState
    /// Promotes a free sticky into a task sticky, creating its linked card. Throws
    /// `OperationError.inconsistentState` when the sticky is **already** a task sticky — a no-op
    /// there would clone a second card and report a phantom success.
    func promoting(id: Sticky.ID, toColumn columnID: Column.ID, in state: BoardState) throws -> BoardState
    /// Demotes a task sticky back to free, removing its linked card and that card's canvas children.
    /// Throws `OperationError.inconsistentState` when the sticky is **already** free (no linked card
    /// to detach) — again, so a no-op never masquerades as success.
    func demoting(id: Sticky.ID, in state: BoardState) throws -> BoardState
    func deleting(id: Sticky.ID, from state: BoardState) throws -> BoardState
}
