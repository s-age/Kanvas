/// Owns the app's ViewModel factories. `@MainActor` because it holds and mints `@MainActor`
/// `@Observable` ViewModels. Receives the `UseCaseContainer` in `init`, extracts the use case
/// existentials its VMs consume, and discards the container (protocol-extraction pattern).
///
/// The board-store watcher is Infrastructure, which this Presentation-layer container may not name.
/// The root `Container` — the one layer that sees all layers — captures the watcher in the injected
/// `startStoreWatching` closure, so this container starts live-refresh without importing
/// Infrastructure. Started exactly once: the `cachedBoardViewModel` guard runs the closure a single
/// time (see `makeBoardViewModel()`).
@MainActor
final class PresentationContainer {
    private let loadBoardViewStateUseCase: LoadBoardViewStateUseCase
    private let loadCardDetailUseCase: any LoadCardDetailUseCase
    private let searchCardsUseCase: any SearchCardsUseCase
    private let listBoardsUseCase: ListBoardsUseCase
    private let addBoardUseCase: AddBoardUseCase
    private let switchBoardUseCase: SwitchBoardUseCase
    private let renameBoardUseCase: RenameBoardUseCase
    private let deleteBoardUseCase: DeleteBoardUseCase
    private let addColumnUseCase: AddColumnUseCase
    private let renameColumnUseCase: RenameColumnUseCase
    private let setCompletionColumnUseCase: SetCompletionColumnUseCase
    private let reorderColumnUseCase: ReorderColumnUseCase
    private let deleteColumnUseCase: DeleteColumnUseCase
    private let addCardUseCase: AddCardUseCase
    private let editCardUseCase: EditCardUseCase
    private let moveCardUseCase: MoveCardUseCase
    private let deleteCardUseCase: DeleteCardUseCase
    private let addStickyUseCase: AddStickyUseCase
    private let duplicateStickyUseCase: DuplicateStickyUseCase
    private let editStickyUseCase: EditStickyUseCase
    private let setStickyTextColorUseCase: SetStickyTextColorUseCase
    private let setStickyFillColorUseCase: SetStickyFillColorUseCase
    private let setStickyFontSizeUseCase: SetStickyFontSizeUseCase
    private let moveStickyUseCase: MoveStickyUseCase
    private let setStickyFrameUseCase: SetStickyFrameUseCase
    private let bringStickyToFrontUseCase: BringStickyToFrontUseCase
    private let sendStickyToBackUseCase: SendStickyToBackUseCase
    private let promoteStickyUseCase: PromoteStickyUseCase
    private let demoteStickyUseCase: DemoteStickyUseCase
    private let deleteStickyUseCase: DeleteStickyUseCase
    private let addShapeUseCase: AddShapeUseCase
    private let moveShapeUseCase: MoveShapeUseCase
    private let resizeShapeUseCase: ResizeShapeUseCase
    private let setShapeStrokeColorUseCase: SetShapeStrokeColorUseCase
    private let setShapeFillColorUseCase: SetShapeFillColorUseCase
    private let setShapeStrokeWidthUseCase: SetShapeStrokeWidthUseCase
    private let bringShapeToFrontUseCase: BringShapeToFrontUseCase
    private let sendShapeToBackUseCase: SendShapeToBackUseCase
    private let deleteShapeUseCase: DeleteShapeUseCase
    private let addTextUseCase: AddTextUseCase
    private let duplicateTextUseCase: DuplicateTextUseCase
    private let editTextUseCase: EditTextUseCase
    private let moveTextUseCase: MoveTextUseCase
    private let resizeTextUseCase: ResizeTextUseCase
    private let setTextColorUseCase: SetTextColorUseCase
    private let setTextFontSizeUseCase: SetTextFontSizeUseCase
    private let bringTextToFrontUseCase: BringTextToFrontUseCase
    private let sendTextToBackUseCase: SendTextToBackUseCase
    private let deleteTextUseCase: DeleteTextUseCase
    private let addImageUseCase: AddImageUseCase
    private let moveImageUseCase: MoveImageUseCase
    private let resizeImageUseCase: ResizeImageUseCase
    private let deleteImageUseCase: DeleteImageUseCase
    private let bringImageToFrontUseCase: BringImageToFrontUseCase
    private let sendImageToBackUseCase: SendImageToBackUseCase
    private let saveImageAssetUseCase: SaveImageAssetUseCase
    private let deleteMarkdownImageUseCase: DeleteMarkdownImageUseCase
    private let loadImageDataUseCase: any LoadImageDataUseCase
    private let sweepOrphanedImageAssetsUseCase: any SweepOrphanedImageAssetsUseCase
    private let reportImageLoadFailureUseCase: any ReportImageLoadFailureUseCase
    private let reportPasteboardWriteFailureUseCase: any ReportPasteboardWriteFailureUseCase
    private let addConnectorUseCase: AddConnectorUseCase
    private let deleteConnectorUseCase: DeleteConnectorUseCase
    private let setConnectorCapUseCase: SetConnectorCapUseCase
    private let setConnectorRoutingUseCase: SetConnectorRoutingUseCase
    private let setConnectorStrokeColorUseCase: SetConnectorStrokeColorUseCase
    private let setConnectorStrokeWidthUseCase: SetConnectorStrokeWidthUseCase
    private let reconnectConnectorUseCase: ReconnectConnectorUseCase
    private let setConnectorWaypointUseCase: SetConnectorWaypointUseCase
    private let moveCanvasGroupUseCase: MoveCanvasGroupUseCase
    private let deleteCanvasGroupUseCase: DeleteCanvasGroupUseCase
    private let addLabelUseCase: AddLabelUseCase
    private let editLabelUseCase: EditLabelUseCase
    private let deleteLabelUseCase: DeleteLabelUseCase
    private let toggleStickyLabelUseCase: ToggleStickyLabelUseCase
    private let editBoardSettingsUseCase: EditBoardSettingsUseCase
    private let loadBoardByIDUseCase: LoadBoardByIDUseCase
    private let loadBoardTemplateUseCase: any LoadBoardTemplateUseCase
    private let editBoardTemplateUseCase: EditBoardTemplateUseCase
    private let undoUseCase: UndoUseCase
    private let recordMarkdownJournalUseCase: RecordMarkdownJournalUseCase
    private let listMarkdownJournalUseCase: any ListMarkdownJournalUseCase
    private let clearMarkdownJournalUseCase: ClearMarkdownJournalUseCase

    /// Begins watching the board store for external writes, invoking `onChange` (debounced) on each.
    /// Injected by the root `Container`, which closes over the Infrastructure `BoardStoreWatcher` so
    /// this Presentation-layer container never names an Infrastructure type.
    private let startStoreWatching: @Sendable (@escaping @Sendable () -> Void) -> Void

    /// `nonisolated` so the `Sendable` root `Container` can build this from its nonisolated `init`:
    /// the body only stores `let` use cases and the closure, touching no main-actor state (the
    /// `cachedBoardViewModel` mutation lives in `makeBoardViewModel()`, on the main actor).
    nonisolated init(
        useCases: UseCaseContainer,
        startStoreWatching: @escaping @Sendable (@escaping @Sendable () -> Void) -> Void
    ) {
        loadBoardViewStateUseCase = useCases.loadBoardViewStateUseCase
        loadCardDetailUseCase = useCases.loadCardDetailUseCase
        searchCardsUseCase = useCases.searchCardsUseCase
        listBoardsUseCase = useCases.listBoardsUseCase
        addBoardUseCase = useCases.addBoardUseCase
        switchBoardUseCase = useCases.switchBoardUseCase
        renameBoardUseCase = useCases.renameBoardUseCase
        deleteBoardUseCase = useCases.deleteBoardUseCase
        addColumnUseCase = useCases.addColumnUseCase
        renameColumnUseCase = useCases.renameColumnUseCase
        setCompletionColumnUseCase = useCases.setCompletionColumnUseCase
        reorderColumnUseCase = useCases.reorderColumnUseCase
        deleteColumnUseCase = useCases.deleteColumnUseCase
        addCardUseCase = useCases.addCardUseCase
        editCardUseCase = useCases.editCardUseCase
        moveCardUseCase = useCases.moveCardUseCase
        deleteCardUseCase = useCases.deleteCardUseCase
        addStickyUseCase = useCases.addStickyUseCase
        duplicateStickyUseCase = useCases.duplicateStickyUseCase
        editStickyUseCase = useCases.editStickyUseCase
        setStickyTextColorUseCase = useCases.setStickyTextColorUseCase
        setStickyFillColorUseCase = useCases.setStickyFillColorUseCase
        setStickyFontSizeUseCase = useCases.setStickyFontSizeUseCase
        moveStickyUseCase = useCases.moveStickyUseCase
        setStickyFrameUseCase = useCases.setStickyFrameUseCase
        bringStickyToFrontUseCase = useCases.bringStickyToFrontUseCase
        sendStickyToBackUseCase = useCases.sendStickyToBackUseCase
        promoteStickyUseCase = useCases.promoteStickyUseCase
        demoteStickyUseCase = useCases.demoteStickyUseCase
        deleteStickyUseCase = useCases.deleteStickyUseCase
        addShapeUseCase = useCases.addShapeUseCase
        moveShapeUseCase = useCases.moveShapeUseCase
        resizeShapeUseCase = useCases.resizeShapeUseCase
        setShapeStrokeColorUseCase = useCases.setShapeStrokeColorUseCase
        setShapeFillColorUseCase = useCases.setShapeFillColorUseCase
        setShapeStrokeWidthUseCase = useCases.setShapeStrokeWidthUseCase
        bringShapeToFrontUseCase = useCases.bringShapeToFrontUseCase
        sendShapeToBackUseCase = useCases.sendShapeToBackUseCase
        deleteShapeUseCase = useCases.deleteShapeUseCase
        addTextUseCase = useCases.addTextUseCase
        duplicateTextUseCase = useCases.duplicateTextUseCase
        editTextUseCase = useCases.editTextUseCase
        moveTextUseCase = useCases.moveTextUseCase
        resizeTextUseCase = useCases.resizeTextUseCase
        setTextColorUseCase = useCases.setTextColorUseCase
        setTextFontSizeUseCase = useCases.setTextFontSizeUseCase
        bringTextToFrontUseCase = useCases.bringTextToFrontUseCase
        sendTextToBackUseCase = useCases.sendTextToBackUseCase
        deleteTextUseCase = useCases.deleteTextUseCase
        addImageUseCase = useCases.addImageUseCase
        moveImageUseCase = useCases.moveImageUseCase
        resizeImageUseCase = useCases.resizeImageUseCase
        deleteImageUseCase = useCases.deleteImageUseCase
        bringImageToFrontUseCase = useCases.bringImageToFrontUseCase
        sendImageToBackUseCase = useCases.sendImageToBackUseCase
        saveImageAssetUseCase = useCases.saveImageAssetUseCase
        deleteMarkdownImageUseCase = useCases.deleteMarkdownImageUseCase
        loadImageDataUseCase = useCases.loadImageDataUseCase
        reportImageLoadFailureUseCase = useCases.reportImageLoadFailureUseCase
        reportPasteboardWriteFailureUseCase = useCases.reportPasteboardWriteFailureUseCase
        sweepOrphanedImageAssetsUseCase = useCases.sweepOrphanedImageAssetsUseCase
        addConnectorUseCase = useCases.addConnectorUseCase
        deleteConnectorUseCase = useCases.deleteConnectorUseCase
        setConnectorCapUseCase = useCases.setConnectorCapUseCase
        setConnectorRoutingUseCase = useCases.setConnectorRoutingUseCase
        setConnectorStrokeColorUseCase = useCases.setConnectorStrokeColorUseCase
        setConnectorStrokeWidthUseCase = useCases.setConnectorStrokeWidthUseCase
        reconnectConnectorUseCase = useCases.reconnectConnectorUseCase
        setConnectorWaypointUseCase = useCases.setConnectorWaypointUseCase
        moveCanvasGroupUseCase = useCases.moveCanvasGroupUseCase
        deleteCanvasGroupUseCase = useCases.deleteCanvasGroupUseCase
        addLabelUseCase = useCases.addLabelUseCase
        editLabelUseCase = useCases.editLabelUseCase
        deleteLabelUseCase = useCases.deleteLabelUseCase
        toggleStickyLabelUseCase = useCases.toggleStickyLabelUseCase
        editBoardSettingsUseCase = useCases.editBoardSettingsUseCase
        loadBoardByIDUseCase = useCases.loadBoardByIDUseCase
        loadBoardTemplateUseCase = useCases.loadBoardTemplateUseCase
        editBoardTemplateUseCase = useCases.editBoardTemplateUseCase
        undoUseCase = useCases.undoUseCase
        recordMarkdownJournalUseCase = useCases.recordMarkdownJournalUseCase
        listMarkdownJournalUseCase = useCases.listMarkdownJournalUseCase
        clearMarkdownJournalUseCase = useCases.clearMarkdownJournalUseCase
        self.startStoreWatching = startStoreWatching
    }

    /// The app's single board ViewModel. Cached so `makeBoardViewModel()` is idempotent: a scene
    /// re-evaluation re-calling the factory must get the same instance — minting a fresh VM would
    /// also restart the store watcher, silently severing live refresh from the previous one.
    private var cachedBoardViewModel: BoardViewModel?

    func makeBoardViewModel() -> BoardViewModel {
        if let cached = cachedBoardViewModel { return cached }
        let viewModel = BoardViewModel(
            loadBoardViewState: loadBoardViewStateUseCase,
            loadCardDetail: loadCardDetailUseCase,
            undo: undoUseCase,
            reportPasteboardWriteFailure: reportPasteboardWriteFailureUseCase,
            management: BoardManagementUseCases(
                list: listBoardsUseCase,
                add: addBoardUseCase,
                switchBoard: switchBoardUseCase,
                rename: renameBoardUseCase,
                delete: deleteBoardUseCase,
                search: searchCardsUseCase
            ),
            kanban: BoardKanbanUseCases(
                addColumn: addColumnUseCase,
                renameColumn: renameColumnUseCase,
                setCompletionColumn: setCompletionColumnUseCase,
                reorderColumn: reorderColumnUseCase,
                deleteColumn: deleteColumnUseCase,
                addCard: addCardUseCase,
                editCard: editCardUseCase,
                moveCard: moveCardUseCase,
                deleteCard: deleteCardUseCase
            ),
            sticky: BoardStickyUseCases(
                add: addStickyUseCase,
                duplicate: duplicateStickyUseCase,
                edit: editStickyUseCase,
                setTextColor: setStickyTextColorUseCase,
                setFillColor: setStickyFillColorUseCase,
                setFontSize: setStickyFontSizeUseCase,
                move: moveStickyUseCase,
                setFrame: setStickyFrameUseCase,
                bringToFront: bringStickyToFrontUseCase,
                sendToBack: sendStickyToBackUseCase,
                promote: promoteStickyUseCase,
                demote: demoteStickyUseCase,
                delete: deleteStickyUseCase
            ),
            shape: BoardShapeUseCases(
                add: addShapeUseCase,
                move: moveShapeUseCase,
                resize: resizeShapeUseCase,
                setStrokeColor: setShapeStrokeColorUseCase,
                setFillColor: setShapeFillColorUseCase,
                setStrokeWidth: setShapeStrokeWidthUseCase,
                bringToFront: bringShapeToFrontUseCase,
                sendToBack: sendShapeToBackUseCase,
                delete: deleteShapeUseCase
            ),
            text: BoardTextUseCases(
                add: addTextUseCase,
                duplicate: duplicateTextUseCase,
                edit: editTextUseCase,
                move: moveTextUseCase,
                resize: resizeTextUseCase,
                setColor: setTextColorUseCase,
                setFontSize: setTextFontSizeUseCase,
                bringToFront: bringTextToFrontUseCase,
                sendToBack: sendTextToBackUseCase,
                delete: deleteTextUseCase
            ),
            image: BoardImageUseCases(
                add: addImageUseCase,
                move: moveImageUseCase,
                resize: resizeImageUseCase,
                delete: deleteImageUseCase,
                bringToFront: bringImageToFrontUseCase,
                sendToBack: sendImageToBackUseCase,
                saveAsset: saveImageAssetUseCase,
                deleteMarkdownImage: deleteMarkdownImageUseCase,
                loadData: loadImageDataUseCase,
                sweepOrphans: sweepOrphanedImageAssetsUseCase,
                reportLoadFailure: reportImageLoadFailureUseCase
            ),
            connector: BoardConnectorUseCases(
                add: addConnectorUseCase,
                delete: deleteConnectorUseCase,
                setCap: setConnectorCapUseCase,
                setRouting: setConnectorRoutingUseCase,
                setStrokeColor: setConnectorStrokeColorUseCase,
                setStrokeWidth: setConnectorStrokeWidthUseCase,
                reconnect: reconnectConnectorUseCase,
                setWaypoint: setConnectorWaypointUseCase
            ),
            group: BoardGroupUseCases(
                move: moveCanvasGroupUseCase,
                delete: deleteCanvasGroupUseCase
            ),
            label: BoardLabelUseCases(
                add: addLabelUseCase,
                edit: editLabelUseCase,
                delete: deleteLabelUseCase,
                toggle: toggleStickyLabelUseCase
            ),
            markdownJournal: BoardMarkdownJournalUseCases(
                record: recordMarkdownJournalUseCase,
                list: listMarkdownJournalUseCase,
                clear: clearMarkdownJournalUseCase
            )
        )
        // Live-refresh: when the MCP server (a separate process) writes the shared store, reload the
        // board so its edits appear without a manual refresh. The watcher fires on our own saves too;
        // `load()` is idempotent at the @Observable level (it reassigns only changed Responses), so a
        // self-echo is a cheap no-op. The root Container bridges Infrastructure → the VM via the
        // injected closure. Started exactly once — the cache above guarantees this branch runs once.
        startStoreWatching { [weak viewModel] in
            Task { @MainActor in await viewModel?.load() }
        }
        cachedBoardViewModel = viewModel
        return viewModel
    }

    func makeSettingsViewModel(boardViewModel: BoardViewModel) -> SettingsViewModel {
        SettingsViewModel(
            boardHost: boardViewModel,
            editBoardSettings: editBoardSettingsUseCase,
            loadBoardByID: loadBoardByIDUseCase,
            loadBoardTemplate: loadBoardTemplateUseCase,
            editBoardTemplate: editBoardTemplateUseCase
        )
    }
}
