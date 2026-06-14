import SwiftUI

@Observable
@MainActor
final class BoardViewModel {

    // MARK: - State

    private(set) var board: BoardResponse?
    private(set) var selectedCardDetail: CardDetailResponse?
    /// All boards for the picker, and which one is active. Driven by the board-management use
    /// cases; kept separate from `board` so the per-board edit flow never touches the picker list.
    private(set) var boards: [BoardSummary] = []
    private(set) var activeBoardID: UUID?
    var selectedCardID: UUID? {
        didSet {
            // Drop the previous card's canvas selection — single + multi — through the one funnel, so
            // there stays exactly one way to empty both buckets.
            clearSelection()
            // The paste buffer is per-canvas: a copy from card A must not paste onto B (and its
            // step counter must not carry over and fling A's next paste far away).
            copiedItem = nil
            pasteCount = 0
            // The label panel targets a sticky on the previous card — close it on a card switch.
            labelManagerStickyID = nil
            refreshCardDetail()
        }
    }
    /// The canvas's current selection — **the single source of truth** for what is selected. Each
    /// member carries its *kind* (sticky/shape/image/connector), so the lone `selection` and the raw
    /// `selectedIDs` both derive from this set with no second bucket to keep in sync. Cleared when the
    /// card changes or the user clicks empty canvas.
    ///
    /// `private(set)`: every write goes through `select(...)`/`toggleSelected`/`selectRegion`/
    /// `clearSelection`/`applyCanvasDelete`, never a raw assignment from another file. There is no
    /// invariant to hand-maintain any more — a single set cannot disagree with itself — so the
    /// `private(set)` here is plain encapsulation, not the desync guard the former (`selection`,
    /// `additionalSelectedIDs`) pair needed.
    ///
    /// **Why a `Set<CanvasSelection>` (kind included) rather than a `Set<UUID>` plus a derived
    /// `selection`?** Deriving the lone `selection` from raw ids would re-run `classifySelection` on
    /// every read, and that lookup needs `selectedCardDetail`. A just-selected item whose detail hasn't
    /// loaded yet would classify to `nil` and briefly show no toolbar (a flicker). Storing the *kind*
    /// at selection time means `select(stickyID:)` etc. set it directly and the toolbar never flickers;
    /// classification happens **once, at write time**, only where the entry point has a raw id
    /// (`toggleSelected`/`selectRegion`), never on read and never again on delete.
    private(set) var selectedItems: Set<CanvasSelection> = []
    /// Internal paste buffer for ⌘C/⌘V — the last copied canvas item (a sticky **or** a text) and
    /// how many times it has been pasted (so repeated pastes step away from the source instead of
    /// stacking). A single optional sum type (`CopiedCanvasItem`) makes "both a sticky and a text
    /// copied" unrepresentable, so no copy site has to clear a sibling by hand. `pasteCount` resets
    /// on every copy. Not `private`: read/written from the `BoardViewModel+StickyActions` /
    /// `+TextActions` extensions (separate files).
    var copiedItem: CopiedCanvasItem?
    var pasteCount: Int = 0
    var isMarkdownExpanded: Bool = true
    var error: (any Error)?

    /// The header search field's text. Editing it debounces a `SearchCardsUseCase` call (see
    /// `BoardViewModel+Search`) that refreshes `matchedCardIDs`. Bound directly by the header field;
    /// cleared on a board switch (search scope is the active board — ticket 59B10FBA).
    var searchText: String = "" {
        didSet { scheduleSearch() }
    }

    /// The active-board card ids matching the current search, or `nil` when no filter is in effect
    /// (blank query). `nil` means "show every card"; a (possibly empty) set means "show only these".
    /// `private(set)`: only the debounced search in `BoardViewModel+Search` writes it.
    private(set) var matchedCardIDs: Set<UUID>?

    /// The in-flight debounced search task, retained so a fresh keystroke cancels the previous one.
    /// `@ObservationIgnored` — pure scheduling plumbing, drives no UI directly (the UI observes
    /// `matchedCardIDs`).
    @ObservationIgnored
    var searchTask: Task<Void, Never>?

    /// A transient, **non-error** informational notice for the user — e.g. "undo skipped because
    /// the board changed externally". Kept distinct from `error`: this is an expected, benign
    /// outcome, not a failure, so surfacing it through the `error` channel would mislabel it under
    /// the "Error" alert. The notice carries its own title (see `UserNotice`) so the presenting
    /// alert isn't coupled to one caller. One-shot; cleared on dismiss.
    var notice: UserNotice?

    /// The sticky the label-management panel targets for assignment, or `nil` when closed.
    /// Single source of truth for the panel — driven by the canvas label icon.
    var labelManagerStickyID: UUID?

    /// The active Markdown image-preview request, or `nil` when the preview window shows nothing
    /// yet (ticket 8511D150). The Markdown gallery sets it on a thumbnail tap (then opens the
    /// reusable preview window via `openWindow`); tapping another thumbnail replaces it, and the
    /// open window re-targets its content. It carries the ordered asset set + index + the board
    /// window's size at open time (the initial-size budget) — not the image bytes, which the
    /// window re-loads via `loadImageData(assetID:)`. The preview is display-only; no use case.
    /// Written only through `openMarkdownImagePreview` / `clearMarkdownImagePreview`
    /// (`BoardViewModel+ImageActions`, a separate file) — those are the only two writers, so the
    /// monotonic open `generation` is always stamped and the close clear is always identity-gated; no
    /// raw assignment from a View. (Not `private(set)` only because the two mutators live in an
    /// extension file.)
    var markdownImagePreview: MarkdownImagePreviewRequest?

    /// Monotonic open token stamped into every `markdownImagePreview` so two otherwise-identical
    /// opens (same image, same index, same unmoved board window) are still distinct values — see
    /// `MarkdownImagePreviewRequest.generation`. Mutated only by `openMarkdownImagePreview`
    /// (`BoardViewModel+ImageActions`). Never reset; only ever increments.
    var markdownImagePreviewGeneration: UInt64 = 0

    /// A just-created free-text object the canvas should enter inline editing on as soon as it
    /// appears (a palette-dropped text starts empty and immediately editable — ticket 7C1D6316 決め事
    /// 3). Set by `addText`, consumed once by `CanvasRepresentable` via `clearTextAwaitingEdit`.
    /// `private(set)`: only `addText` (a separate file) writes it, via `requestTextEdit`.
    private(set) var textAwaitingEdit: UUID?

    /// Records the id of a freshly-added text so the canvas opens its editor. Called from
    /// `BoardViewModel+TextActions` (a separate file), hence not `private`.
    func requestTextEdit(id: UUID) {
        textAwaitingEdit = id
    }

    /// Clears the pending text-edit request once the canvas has begun editing it.
    func clearTextAwaitingEdit() {
        textAwaitingEdit = nil
    }

    /// Guards the orphan-asset GC to run **once per launch**. `performStartupMaintenance()` is the
    /// `.task`-bound caller and may re-fire on board-view re-appearance; the sweep is intended for
    /// startup only — when the per-process undo ring is empty, so it can never strip an asset an undo
    /// would restore. Read/written from the `BoardViewModel+ImageActions` extension, so not `private`.
    /// `@ObservationIgnored` — a pure launch guard driving no UI; without it, flipping it would emit a
    /// spurious `@Observable` change (matches `didRestoreMarkdownJournal`).
    @ObservationIgnored
    var hasSweptOrphanAssets = false

    // MARK: - Dependencies
    //
    // Use cases are injected as per-feature bundle structs (one per action-extension file) so the
    // initializer stays small and a new canvas element no longer threads 6–8 args through the VM,
    // init, and Container. The two read-model use cases and the canvas-wide `undo` below are consumed
    // by this file directly;
    // every bundle is consumed by its matching `BoardViewModel+*Actions` extension (a separate
    // file), so the bundles cannot be `private` (file-scoped).

    private let loadBoardViewStateUseCase: LoadBoardViewStateUseCase
    private let loadCardDetailUseCase: any LoadCardDetailUseCase
    /// Canvas-wide undo — reverts the latest mutation of any element (sticky / shape / connector /
    /// image), so it is a direct VM dependency, not part of the sticky bundle. Consumed by the
    /// `BoardViewModel+StickyActions` extension (its sole caller), hence not `private`.
    let undoUseCase: UndoUseCase
    /// Diagnostics-only port for a failed copy-to-pasteboard write. Presentation cannot reach the
    /// diagnostics capability port directly, so the fire-and-forget use case bridges it (mirrors
    /// `imageUseCases.reportLoadFailure`). Consumed by `reportPasteboardWriteFailure` below.
    private let reportPasteboardWriteFailureUseCase: any ReportPasteboardWriteFailureUseCase
    let managementUseCases: BoardManagementUseCases
    let kanbanUseCases: BoardKanbanUseCases
    let stickyUseCases: BoardStickyUseCases
    let shapeUseCases: BoardShapeUseCases
    let textUseCases: BoardTextUseCases
    let imageUseCases: BoardImageUseCases
    let connectorUseCases: BoardConnectorUseCases
    let groupUseCases: BoardGroupUseCases
    let labelUseCases: BoardLabelUseCases
    let markdownJournalUseCases: BoardMarkdownJournalUseCases

    /// Cards with an unsaved Markdown edit the autosave channel gave up on after a *retainable*
    /// failure (disk full, lock contention) — the durable journal still holds the text — mapped to
    /// each edit's `enqueuedAt` ("unsaved since …"). Drives the editor's manual Retry/Discard
    /// banner. Recomputed from `markdownAutosave` whenever it signals a change. Observed (not
    /// `@ObservationIgnored`) so the banner re-renders. A plain `var` (not `private(set)`): it is
    /// updated from the `+CardActions` file-split extension, same as the other cross-file VM state.
    var unsavedMarkdownEdits: [UUID: Date] = [:]

    /// One-shot guard so the startup journal restore runs once, not on every
    /// `performStartupMaintenance()` (its `.task` caller may re-fire on board-view re-appearance).
    @ObservationIgnored
    private var didRestoreMarkdownJournal = false

    /// Serialized, coalescing autosave channel for Markdown notes. Lives here (not in the
    /// editor view) so a write survives the view disappearing and retries off the view's
    /// lifecycle (ticket B817F0D2). `lazy` + `@ObservationIgnored`: it captures `self` in its
    /// write closure, so it cannot be a plain stored-property initializer (that would escape
    /// `self` before init completes); it drives no rendering, so it is not observed. Consumed
    /// via `enqueueMarkdownSave` / `hasPendingMarkdownSave` in the `+CardActions` extension —
    /// hence not `private` (file-scoped), same as the use-case bundles above.
    @ObservationIgnored
    lazy var markdownAutosave = MarkdownAutosaveQueue(
        dependencies: MarkdownAutosaveQueue.Dependencies(
            write: { [weak self] cardID, content in
                await self?.persistMarkdown(cardID: cardID, content: content)
            },
            journal: { [weak self] cardID, content, enqueuedAt in
                await self?.journalMarkdown(cardID: cardID, content: content, enqueuedAt: enqueuedAt)
            },
            clearJournal: { [weak self] cardID in
                await self?.clearMarkdownJournal(cardID: cardID)
            },
            isRetainable: { error in
                // A deterministic "no save target" failure (the card was deleted → `notFound`) is not
                // worth retaining — it would pin the gate forever. Any other failure (disk full, lock
                // contention) is a recoverable transient whose edit we keep.
                if let opError = error as? OperationError, case .notFound = opError { return false }
                return true
            },
            onError: { [weak self] error in self?.error = error },
            onUnsavedChange: { [weak self] in self?.refreshUnsavedMarkdown() }
        )
    )

    // MARK: - Init

    init(
        loadBoardViewState: LoadBoardViewStateUseCase,
        loadCardDetail: any LoadCardDetailUseCase,
        undo: UndoUseCase,
        reportPasteboardWriteFailure: any ReportPasteboardWriteFailureUseCase,
        management: BoardManagementUseCases,
        kanban: BoardKanbanUseCases,
        sticky: BoardStickyUseCases,
        shape: BoardShapeUseCases,
        text: BoardTextUseCases,
        image: BoardImageUseCases,
        connector: BoardConnectorUseCases,
        group: BoardGroupUseCases,
        label: BoardLabelUseCases,
        markdownJournal: BoardMarkdownJournalUseCases
    ) {
        loadBoardViewStateUseCase = loadBoardViewState
        loadCardDetailUseCase = loadCardDetail
        undoUseCase = undo
        reportPasteboardWriteFailureUseCase = reportPasteboardWriteFailure
        managementUseCases = management
        kanbanUseCases = kanban
        stickyUseCases = sticky
        shapeUseCases = shape
        textUseCases = text
        imageUseCases = image
        connectorUseCases = connector
        groupUseCases = group
        labelUseCases = label
        markdownJournalUseCases = markdownJournal
    }

    // MARK: - Actions

    /// Diagnostics only: a copy-to-pasteboard write returned `false` (clipboard left unchanged).
    /// Forwards to the fire-and-forget logging use case so the failure reaches Console — Presentation
    /// cannot reach the diagnostics port directly. `label` names what was being copied (ticket 8E857E6F).
    func reportPasteboardWriteFailure(label: String) {
        reportPasteboardWriteFailureUseCase.execute(label: label)
    }

    /// Read-only board refresh. Re-reads the store and republishes the board + picker, nothing more.
    /// **Must stay read-only**: this is also the store-watcher callback (`startStoreWatching` fires it
    /// on every external write) and a model told "call `load()` to refresh" cannot predict a write.
    /// The once-per-launch maintenance that *does* write — orphan-asset GC, Markdown-journal restore —
    /// lives in `performStartupMaintenance()`, called once from the board scene (ticket 7935A21E).
    func load() async {
        do {
            // One store read for the whole refresh — board + picker list + open-card detail — instead
            // of the former `loadActiveBoard` → `loadBoards` → `refreshCardDetail → loadActiveBoard`
            // chain that paid three flock + decode round-trips of the same snapshot per external-change
            // watcher fire (ticket 8DCB811D). The open card's detail is mapped from the same decoded
            // state, so an external sticky edit to it still surfaces (ticket 18CA57E0).
            // Pass the active filter text so the use case applies it over the same decoded state and
            // returns the matched ids — sparing the second store read the former
            // `refreshSearchIfActive` → `SearchCards` round-trip paid on every filtered refresh
            // (PR #123 r2-1). A blank query yields a `nil` filter (show every card).
            let response = try await loadBoardViewStateUseCase.execute(
                LoadBoardViewStateRequest(openCardID: selectedCardID, searchQuery: searchText)
            )
            applyBoardViewState(response)
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }

    /// One-shot startup maintenance, deliberately **outside** `load()` so the read-only refresh — which
    /// the store watcher fires on every external write — can never trigger a write. Both steps below
    /// write (the GC deletes asset files; the restore re-enqueues saves), and both are internally
    /// guarded to run once per launch, where the per-process undo ring is empty so the GC can never
    /// strip an asset an undo would restore. Fully best-effort. Called once from the board scene's
    /// `.task` (ticket 7935A21E).
    func performStartupMaintenance() async {
        // The caller is the board scene's `.task`, which `load()` runs ahead of us; `load()` swallows
        // its own cancellation and returns, so without this guard we would start maintenance in an
        // already-cancelled context. `sweepOrphanedImageAssets()` flips its once-per-launch guard
        // *before* awaiting, so a sweep begun while cancelled would mark itself done without finishing
        // and never retry this session. Bail before either step so both stay retryable next launch.
        guard !Task.isCancelled else { return }
        await sweepOrphanedImageAssets()
        await restorePendingMarkdownSaves()
    }

    /// Re-enqueue any Markdown edits the durable journal still holds — edits stranded by an app
    /// quit/crash or a give-up (ticket 44C9D3C2). Runs once per session (guarded below); best-effort,
    /// so a read failure never blocks the board. Driven by `performStartupMaintenance()`.
    private func restorePendingMarkdownSaves() async {
        guard !didRestoreMarkdownJournal else { return }
        // Flip the once-per-launch guard **only after a successful read**. The journal store throws
        // (and logs the cause) when its directory won't enumerate; setting the guard *before* the
        // read would silently skip restore for the rest of the session with no retry (ticket
        // 7DA7C85F). Leaving it unset lets `performStartupMaintenance()` re-attempt on the next
        // board-view re-appearance. A successful read with no entries still flips it — there is
        // genuinely nothing to restore.
        guard let edits = try? await markdownJournalUseCases.list.execute() else { return }
        didRestoreMarkdownJournal = true
        markdownAutosave.restore(
            edits.map { (cardID: $0.cardID, content: $0.content, enqueuedAt: $0.enqueuedAt) }
        )
    }

    func selectCard(id: UUID?) {
        selectedCardID = id
    }

    func dismissError() {
        error = nil
    }

    func dismissNotice() {
        notice = nil
    }

    /// Publishes a search result (or clears the filter with `nil`). The sole writer of the
    /// `private(set) matchedCardIDs`, so the debounced search in `BoardViewModel+Search` (a separate
    /// file) routes its result through here.
    func applyMatchedCardIDs(_ ids: Set<UUID>?) {
        matchedCardIDs = ids
    }
}


// MARK: - Derived read-model + selection
//
// Computed read-model accessors and the selection entry points live in a same-file extension so
// the class body stays within the type-body-length budget.

extension BoardViewModel {

    /// Whether the panel is open — derived from its target, so the two can never disagree.
    var isLabelManagerPresented: Bool { labelManagerStickyID != nil }

    /// The full app-wide label registry — the manager panel's list source.
    var labels: [StickyLabelResponse] { board?.labels ?? [] }

    /// The sticky the label manager currently targets, read live so assignment checkmarks update.
    var labelManagerSticky: StickyResponse? {
        guard let id = labelManagerStickyID else { return nil }
        return selectedCardDetail?.stickies.first { $0.id == id }
    }

    var errorMessage: String? {
        error?.localizedDescription
    }

    /// The selected sticky's current Response, read live so the toolbar reflects style edits.
    var selectedSticky: StickyResponse? {
        guard let id = selection?.stickyID else { return nil }
        return selectedCardDetail?.stickies.first { $0.id == id }
    }

    /// The current board's palette presets (label / colour / absolute size), read live so the
    /// sticky tray reflects edits made in Settings → Canvas. Empty until a board has loaded.
    var stickyPresets: [StickyPresetResponse] {
        board?.settings.canvas.stickyPresets ?? []
    }

    /// The selected shape's current Response, read live so the shape toolbar reflects style edits.
    var selectedShape: ShapeResponse? {
        guard let id = selection?.shapeID else { return nil }
        return selectedCardDetail?.shapes.first { $0.id == id }
    }

    /// The selected image's current Response, read live so the canvas reflects move/resize edits.
    var selectedImage: ImageResponse? {
        guard let id = selection?.imageID else { return nil }
        return selectedCardDetail?.images.first { $0.id == id }
    }

    /// The selected connector's current Response, read live so the connector toolbar reflects edits.
    var selectedConnector: ConnectorResponse? {
        guard let id = selection?.connectorID else { return nil }
        return selectedCardDetail?.connectors.first { $0.id == id }
    }

    /// The selected free-text object's current Response, read live so the text toolbar reflects edits.
    var selectedText: TextResponse? {
        guard let id = selection?.textID else { return nil }
        return selectedCardDetail?.texts.first { $0.id == id }
    }

    /// The complete canvas selection as raw ids — the canvas highlights every id in here and group
    /// move/delete act on it. Derived from `selectedItems`, so it can never disagree with it.
    var selectedIDs: Set<UUID> {
        Set(selectedItems.map(\.id))
    }

    /// The **single** selection — non-nil only when exactly one item is selected, so the per-kind
    /// toolbar (colour/size) shows for a lone selection and hides once a second item joins. Derived
    /// from `selectedItems`, and the lone member already carries its kind, so reading this never
    /// re-classifies and never flickers. (Colour/size edits intentionally don't apply to a
    /// multi-selection.)
    var selection: CanvasSelection? {
        selectedItems.count == 1 ? selectedItems.first : nil
    }

    /// Selection entry points from the canvas. The selection is a single sum type, so targeting a
    /// sticky inherently clears any shape selection and vice versa; `nil` clears it (empty-canvas
    /// click). The canvas knows the hit item's kind from its merged list and calls the matching one.
    /// A plain (non-additive) select replaces the whole selection. The kind is recorded here directly,
    /// so the lone selection's toolbar resolves immediately even before `selectedCardDetail` loads.
    func select(stickyID: UUID?) {
        selectedItems = stickyID.map { [CanvasSelection.sticky($0)] } ?? []
    }

    func select(shapeID: UUID?) {
        selectedItems = shapeID.map { [CanvasSelection.shape($0)] } ?? []
    }

    func select(imageID: UUID?) {
        selectedItems = imageID.map { [CanvasSelection.image($0)] } ?? []
    }

    func select(textID: UUID?) {
        selectedItems = textID.map { [CanvasSelection.text($0)] } ?? []
    }

    func select(connectorID: UUID?) {
        selectedItems = connectorID.map { [CanvasSelection.connector($0)] } ?? []
    }

    /// ⌘-click on an item: toggle its membership in the selection (add if absent, remove if present).
    /// Removal needs no kind (match by id); addition classifies the raw id once, here — an id no
    /// longer in the open card's detail simply isn't added.
    func toggleSelected(id: UUID) {
        if let existing = selectedItems.first(where: { $0.id == id }) {
            selectedItems.remove(existing)
        } else if let resolved = classifySelection(id) {
            selectedItems.insert(resolved)
        }
        assertOneKindPerID()
    }

    /// Marquee (rubber-band) result: select every item the region caught. `additive` (⌘ held) unions
    /// with the current selection instead of replacing it. Each raw id is classified once here; an id
    /// that no longer resolves to a canvas item is dropped — so a lone unresolved id clears the
    /// selection rather than landing as a stray, kind-less member (ticket CB849222).
    func selectRegion(ids: Set<UUID>, additive: Bool) {
        let resolved = Set(ids.compactMap(classifySelection))
        selectedItems = additive ? selectedItems.union(resolved) : resolved
        assertOneKindPerID()
    }

    /// Clears the whole selection in one write — the only way another file may empty `selectedItems`
    /// now that it is `private(set)`.
    func clearSelection() {
        selectedItems = []
    }

    /// Resolves an id to its selection kind by looking it up in the open card's detail — the same
    /// way the canvas routes by kind from its merged list. `nil` if the id is no longer present.
    private func classifySelection(_ id: UUID) -> CanvasSelection? {
        guard let detail = selectedCardDetail else { return nil }
        if detail.stickies.contains(where: { $0.id == id }) { return .sticky(id) }
        if detail.shapes.contains(where: { $0.id == id }) { return .shape(id) }
        if detail.images.contains(where: { $0.id == id }) { return .image(id) }
        if detail.texts.contains(where: { $0.id == id }) { return .text(id) }
        if detail.connectors.contains(where: { $0.id == id }) { return .connector(id) }
        return nil
    }

    /// Pins the one-kind-per-id invariant the derived views rely on: `selectedIDs` (a `Set<UUID>`)
    /// and `selection` (nil unless `count == 1`) only agree while no id appears under two kinds.
    /// `Set<CanvasSelection>` cannot enforce this at the type level — `{.sticky(x), .shape(x)}` is two
    /// distinct members — so the guarantee rests on the entry points: `classifySelection` is a
    /// deterministic id→kind function for one `selectedCardDetail`, so neither the `insert` nor the
    /// `union` above can pair an id with a second kind. This `assert` documents and pins that (PR #83
    /// review nit 1); it compiles out of release builds.
    private func assertOneKindPerID() {
        assert(selectedItems.count == selectedIDs.count,
               "selectedItems holds an id under two kinds — selectedIDs/selection would desync")
    }
}

// MARK: - Board / card-detail publishing
//
// Kept in a same-file extension (not the class body) so the type stays within the body-length
// budget while these helpers retain access to the type's private state.

extension BoardViewModel {

    /// Internal (not private) so the `BoardViewModel+StickyActions` extension — in a separate
    /// file — can publish its results too.
    func applyBoard(_ response: BoardResponse) {
        // Assign only on a real change so a redundant reload (e.g. the file-watcher firing on our
        // own save) doesn't churn the UI. The card detail is refreshed unconditionally: stickies
        // live in `CardDetailResponse`, not `BoardResponse`, so an external sticky edit can change
        // the open card without changing `board`.
        if board != response { board = response }
        refreshCardDetail()
    }

    /// Publishes a full board refresh assembled from a **single** store read (ticket 8DCB811D): the
    /// picker list, the board, and the open card's detail derived from the same decoded snapshot.
    /// Replaces the old `loadActiveBoard → applyBoard(→refreshCardDetail→loadActiveBoard) → loadBoards`
    /// chain, which paid three separate flock + decode round-trips per external-change watcher fire.
    ///
    /// The picker list (`boards` + `activeBoardID`) is assigned **unconditionally** via
    /// `applyBoardList` — those are small `private(set)` arrays the picker re-renders cheaply. The
    /// `board` and the open card's `selectedCardDetail` carry the self-echo suppression (assigned only
    /// on a real change — see `applyBoard` / `adoptOpenCardDetail`, ticket 5BC2FF20) because they drive
    /// the heavy board + canvas redraw. The open card's detail is adopted directly when the snapshot
    /// supplied it, falling back to a disk reload only when the open card no longer resolves (e.g.
    /// deleted by the other process while still open) — the rare path that still needs a second read.
    func applyBoardViewState(_ response: BoardViewStateResponse) {
        applyBoardList(response.boardList)
        if board != response.board { board = response.board }
        if !adoptOpenCardDetail(response.cardDetail) { refreshCardDetail() }
        // A live refresh (store-watcher fire, in-app or MCP card edit) can change which cards match
        // the active filter; the use case already re-ran the matcher over the **same** decoded state
        // (no second store read — PR #123 r2-1), so adopt its result rather than firing another
        // `SearchCards` round-trip. Guarded against a stale landing inside `BoardViewModel+Search`.
        adoptRefreshedMatch(response.matchedCardIDs, for: response.matchedQuery)
    }

    /// Publishes a canvas/card mutation that already carries the affected card's refreshed detail.
    /// Updates `board` only on a real change (the self-echo suppression from `applyBoard`), then
    /// adopts the returned `cardDetail` directly when it is the open card — skipping the disk
    /// re-read the old `applyBoard → refreshCardDetail → LoadCardDetail → loadActiveBoard` path always paid
    /// (ticket 1DCBF9C9). Falls back to a fresh load only when the mutation supplied no detail for
    /// the open card (a board/column/label-registry op, or a cross-card edit).
    func applyBoardMutation(_ response: BoardMutationResponse) {
        if board != response.board { board = response.board }
        // Fall back to the fire-and-forget disk reload when the mutation carried no detail for the
        // open card (a board/column/label-registry op, or a cross-card edit).
        if !adoptOpenCardDetail(response.cardDetail) { refreshCardDetail() }
    }

    /// Adopts a mutation's returned card detail **iff** it is the open card, assigning only on a
    /// real change (the self-echo suppression from `applyBoard`). Returns whether it adopted, so the
    /// caller picks the fallback reload strategy (fire-and-forget here vs awaited in
    /// `applyBoardMutationAwaitingDetail`). A `nil` or different-card detail returns `false`.
    private func adoptOpenCardDetail(_ detail: CardDetailResponse?) -> Bool {
        guard let detail, detail.id == selectedCardID else { return false }
        if selectedCardDetail != detail { selectedCardDetail = detail }
        return true
    }

    /// Publishes the catalog-backed board list + active id. Lives in this file (not the separate
    /// `BoardViewModel+BoardManagement` file) because it sets the `private(set)` picker state.
    func applyBoardList(_ response: BoardListResponse) {
        boards = response.boards
        activeBoardID = response.activeBoardID
    }

    /// `applyBoardMutation` whose card-detail refresh can be awaited. The plain variant refreshes a
    /// *fallback* reload fire-and-forget, so a caller that just mutated the stickies (e.g. paste)
    /// cannot see the new sticky synchronously after it returns. The mutation normally carries the
    /// open card's refreshed detail, which is adopted synchronously here; only the fallback (no
    /// detail for the open card) awaits a disk reload. Use this when the next step must act on the
    /// refreshed stickies.
    func applyBoardMutationAwaitingDetail(_ response: BoardMutationResponse) async {
        if board != response.board { board = response.board }
        if !adoptOpenCardDetail(response.cardDetail) { await reloadSelectedCardDetail() }
    }

    /// Publishes the board produced by a canvas delete, then clears the selection when it targeted
    /// the just-removed item. A `notFound` is treated as a **silent no-op**: the element is already
    /// gone — a second ⌫ on a stale selection, or another process deleted it first — which is the
    /// idempotent outcome the delete intended, so it must not raise an alert (it was a no-op before
    /// delete gerunds started throwing `notFound`). Only genuine failures reach `error`. MCP deletes
    /// bypass this handler, so the model still sees `notFound`.
    func applyCanvasDelete(id: UUID, _ delete: () async throws -> BoardMutationResponse) async {
        do {
            applyBoardMutation(try await delete())
        } catch OperationError.notFound {
            // Already gone — the delete is idempotent from the UI's perspective.
        } catch {
            self.error = error
            return
        }
        // Drop the removed item from the selection set. Survivors keep the kind they were selected
        // with, so a now-lone survivor re-promotes into `selection` (its toolbar shows) without any
        // re-classification — there is no dependence on `selectedCardDetail` being fresh here, unlike
        // the former subtract-and-re-classify path.
        selectedItems = selectedItems.filter { $0.id != id }
    }

    private func refreshCardDetail() {
        guard selectedCardID != nil else {
            selectedCardDetail = nil
            return
        }
        Task { await reloadSelectedCardDetail() }
    }

    /// Loads the selected card's detail (stickies + metadata) and assigns it. Awaitable so a
    /// caller that just mutated the board can act on the refreshed stickies before continuing.
    /// `private` — every caller lives in this file (`refreshCardDetail` / `applyBoardMutationAwaitingDetail`).
    private func reloadSelectedCardDetail() async {
        guard let cardID = selectedCardID else {
            selectedCardDetail = nil
            return
        }
        do {
            let detail = try await loadCardDetailUseCase.execute(cardID: cardID)
            guard selectedCardID == cardID else { return }
            // Assign only on a real change — see `applyBoard`; keeps a self-echo reload from churning.
            if selectedCardDetail != detail { selectedCardDetail = detail }
        } catch is CancellationError {
            return
        } catch {
            self.error = error
        }
    }
}
