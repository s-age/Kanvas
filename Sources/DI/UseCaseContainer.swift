/// Owns every use case instance, built from the Domain service protocols. Use cases no longer hold
/// any Repository — each Service owns the `repository.mutate` boundary — so this container takes
/// only the `DomainContainer`, extracts the service existentials it needs as locals, and discards
/// the container (protocol-extraction pattern); it stores only the use cases. Also vends the MCP
/// gateway, since that façade is a pure bundle of use cases (see `makeMCPGateway()`).
final class UseCaseContainer: Sendable {
    // These use cases are intentionally internal `let` (not `private`): `PresentationContainer`
    // reads them in its `init` to extract the existentials its ViewModels need. Do not tighten to
    // `private` — that breaks the cross-container extraction. (`PresentationContainer`, by contrast,
    // is a leaf consumer, so its copies are `private let`.)
    let loadActiveBoardUseCase: LoadActiveBoardUseCase
    let loadBoardViewStateUseCase: LoadBoardViewStateUseCase
    let loadCardDetailUseCase: any LoadCardDetailUseCase
    let searchCardsUseCase: any SearchCardsUseCase
    let listBoardsUseCase: ListBoardsUseCase
    let addBoardUseCase: AddBoardUseCase
    let switchBoardUseCase: SwitchBoardUseCase
    let renameBoardUseCase: RenameBoardUseCase
    let deleteBoardUseCase: DeleteBoardUseCase
    let addColumnUseCase: AddColumnUseCase
    let renameColumnUseCase: RenameColumnUseCase
    let setCompletionColumnUseCase: SetCompletionColumnUseCase
    let reorderColumnUseCase: ReorderColumnUseCase
    let deleteColumnUseCase: DeleteColumnUseCase
    let addCardUseCase: AddCardUseCase
    let editCardUseCase: EditCardUseCase
    let moveCardUseCase: MoveCardUseCase
    let deleteCardUseCase: DeleteCardUseCase
    let addStickyUseCase: AddStickyUseCase
    let duplicateStickyUseCase: DuplicateStickyUseCase
    let editStickyUseCase: EditStickyUseCase
    let setStickyTextColorUseCase: SetStickyTextColorUseCase
    let setStickyFillColorUseCase: SetStickyFillColorUseCase
    let setStickyFontSizeUseCase: SetStickyFontSizeUseCase
    let moveStickyUseCase: MoveStickyUseCase
    let setStickyFrameUseCase: SetStickyFrameUseCase
    let bringStickyToFrontUseCase: BringStickyToFrontUseCase
    let sendStickyToBackUseCase: SendStickyToBackUseCase
    let promoteStickyUseCase: PromoteStickyUseCase
    let demoteStickyUseCase: DemoteStickyUseCase
    let deleteStickyUseCase: DeleteStickyUseCase
    let addShapeUseCase: AddShapeUseCase
    let moveShapeUseCase: MoveShapeUseCase
    let resizeShapeUseCase: ResizeShapeUseCase
    let setShapeStrokeColorUseCase: SetShapeStrokeColorUseCase
    let setShapeFillColorUseCase: SetShapeFillColorUseCase
    let setShapeStrokeWidthUseCase: SetShapeStrokeWidthUseCase
    let bringShapeToFrontUseCase: BringShapeToFrontUseCase
    let sendShapeToBackUseCase: SendShapeToBackUseCase
    let deleteShapeUseCase: DeleteShapeUseCase
    let addTextUseCase: AddTextUseCase
    let duplicateTextUseCase: DuplicateTextUseCase
    let editTextUseCase: EditTextUseCase
    let moveTextUseCase: MoveTextUseCase
    let resizeTextUseCase: ResizeTextUseCase
    let setTextColorUseCase: SetTextColorUseCase
    let setTextFontSizeUseCase: SetTextFontSizeUseCase
    let bringTextToFrontUseCase: BringTextToFrontUseCase
    let sendTextToBackUseCase: SendTextToBackUseCase
    let deleteTextUseCase: DeleteTextUseCase
    let addImageUseCase: AddImageUseCase
    let moveImageUseCase: MoveImageUseCase
    let resizeImageUseCase: ResizeImageUseCase
    let deleteImageUseCase: DeleteImageUseCase
    let bringImageToFrontUseCase: BringImageToFrontUseCase
    let sendImageToBackUseCase: SendImageToBackUseCase
    let saveImageAssetUseCase: SaveImageAssetUseCase
    let deleteMarkdownImageUseCase: DeleteMarkdownImageUseCase
    let loadImageDataUseCase: any LoadImageDataUseCase
    let sweepOrphanedImageAssetsUseCase: any SweepOrphanedImageAssetsUseCase
    let reportImageLoadFailureUseCase: any ReportImageLoadFailureUseCase
    let reportPasteboardWriteFailureUseCase: any ReportPasteboardWriteFailureUseCase
    let addConnectorUseCase: AddConnectorUseCase
    let deleteConnectorUseCase: DeleteConnectorUseCase
    let setConnectorCapUseCase: SetConnectorCapUseCase
    let setConnectorRoutingUseCase: SetConnectorRoutingUseCase
    let setConnectorStrokeColorUseCase: SetConnectorStrokeColorUseCase
    let setConnectorStrokeWidthUseCase: SetConnectorStrokeWidthUseCase
    let setConnectorStyleUseCase: SetConnectorStyleUseCase
    let reconnectConnectorUseCase: ReconnectConnectorUseCase
    let setConnectorWaypointUseCase: SetConnectorWaypointUseCase
    let moveCanvasGroupUseCase: MoveCanvasGroupUseCase
    let deleteCanvasGroupUseCase: DeleteCanvasGroupUseCase
    let addLabelUseCase: AddLabelUseCase
    let editLabelUseCase: EditLabelUseCase
    let deleteLabelUseCase: DeleteLabelUseCase
    let toggleStickyLabelUseCase: ToggleStickyLabelUseCase
    let editBoardSettingsUseCase: EditBoardSettingsUseCase
    let editColumnAppearanceUseCase: EditColumnAppearanceUseCase
    let loadBoardByIDUseCase: LoadBoardByIDUseCase
    let loadBoardTemplateUseCase: any LoadBoardTemplateUseCase
    let editBoardTemplateUseCase: EditBoardTemplateUseCase
    let undoUseCase: UndoUseCase
    let recordMarkdownJournalUseCase: RecordMarkdownJournalUseCase
    let listMarkdownJournalUseCase: any ListMarkdownJournalUseCase
    let clearMarkdownJournalUseCase: ClearMarkdownJournalUseCase

    init(domain: DomainContainer) {
        let columnService = domain.columnService
        let cardService = domain.cardService
        let stickyService = domain.stickyService
        let shapeService = domain.shapeService
        let textService = domain.textService
        let imageService = domain.imageService
        let connectorService = domain.connectorService
        let canvasGroupService = domain.canvasGroupService
        let labelService = domain.labelService
        let boardManagement = domain.boardManagementService
        let markdownJournalService = domain.markdownJournalService

        loadActiveBoardUseCase = LoadActiveBoardUseCaseImpl(boardManagement: boardManagement)
        loadBoardViewStateUseCase = LoadBoardViewStateUseCaseImpl(boardManagement: boardManagement)
        loadCardDetailUseCase = LoadCardDetailUseCaseImpl(boardManagement: boardManagement)
        searchCardsUseCase = SearchCardsUseCaseImpl(boardManagement: boardManagement)
        listBoardsUseCase = ListBoardsUseCaseImpl(boardManagement: boardManagement)
        addBoardUseCase = ValidationAsyncUseCaseDecorator(AddBoardUseCaseImpl(boardManagement: boardManagement))
        switchBoardUseCase = SwitchBoardUseCaseImpl(boardManagement: boardManagement)
        renameBoardUseCase = ValidationAsyncUseCaseDecorator(RenameBoardUseCaseImpl(boardManagement: boardManagement))
        deleteBoardUseCase = DeleteBoardUseCaseImpl(boardManagement: boardManagement)
        addColumnUseCase = ValidationAsyncUseCaseDecorator(AddColumnUseCaseImpl(columnService: columnService))
        renameColumnUseCase = ValidationAsyncUseCaseDecorator(RenameColumnUseCaseImpl(columnService: columnService))
        setCompletionColumnUseCase = SetCompletionColumnUseCaseImpl(columnService: columnService)
        reorderColumnUseCase = ReorderColumnUseCaseImpl(columnService: columnService)
        deleteColumnUseCase = DeleteColumnUseCaseImpl(columnService: columnService)
        addCardUseCase = ValidationAsyncUseCaseDecorator(AddCardUseCaseImpl(cardService: cardService))
        editCardUseCase = ValidationAsyncUseCaseDecorator(EditCardUseCaseImpl(cardService: cardService))
        moveCardUseCase = MoveCardUseCaseImpl(cardService: cardService)
        deleteCardUseCase = DeleteCardUseCaseImpl(cardService: cardService)
        addStickyUseCase = ValidationAsyncUseCaseDecorator(AddStickyUseCaseImpl(stickyService: stickyService))
        duplicateStickyUseCase = DuplicateStickyUseCaseImpl(stickyService: stickyService)
        editStickyUseCase = ValidationAsyncUseCaseDecorator(EditStickyUseCaseImpl(stickyService: stickyService))
        setStickyTextColorUseCase = ValidationAsyncUseCaseDecorator(SetStickyTextColorUseCaseImpl(stickyService: stickyService))
        setStickyFillColorUseCase = ValidationAsyncUseCaseDecorator(SetStickyFillColorUseCaseImpl(stickyService: stickyService))
        setStickyFontSizeUseCase = ValidationAsyncUseCaseDecorator(SetStickyFontSizeUseCaseImpl(stickyService: stickyService))
        moveStickyUseCase = ValidationAsyncUseCaseDecorator(MoveStickyUseCaseImpl(stickyService: stickyService))
        setStickyFrameUseCase = ValidationAsyncUseCaseDecorator(SetStickyFrameUseCaseImpl(stickyService: stickyService))
        bringStickyToFrontUseCase = BringStickyToFrontUseCaseImpl(stickyService: stickyService)
        sendStickyToBackUseCase = SendStickyToBackUseCaseImpl(stickyService: stickyService)
        promoteStickyUseCase = PromoteStickyUseCaseImpl(stickyService: stickyService)
        demoteStickyUseCase = DemoteStickyUseCaseImpl(stickyService: stickyService)
        deleteStickyUseCase = DeleteStickyUseCaseImpl(stickyService: stickyService)
        addShapeUseCase = ValidationAsyncUseCaseDecorator(AddShapeUseCaseImpl(shapeService: shapeService))
        moveShapeUseCase = ValidationAsyncUseCaseDecorator(MoveShapeUseCaseImpl(shapeService: shapeService))
        resizeShapeUseCase = ValidationAsyncUseCaseDecorator(ResizeShapeUseCaseImpl(shapeService: shapeService))
        setShapeStrokeColorUseCase = ValidationAsyncUseCaseDecorator(SetShapeStrokeColorUseCaseImpl(shapeService: shapeService))
        setShapeFillColorUseCase = ValidationAsyncUseCaseDecorator(SetShapeFillColorUseCaseImpl(shapeService: shapeService))
        setShapeStrokeWidthUseCase = ValidationAsyncUseCaseDecorator(SetShapeStrokeWidthUseCaseImpl(shapeService: shapeService))
        bringShapeToFrontUseCase = BringShapeToFrontUseCaseImpl(shapeService: shapeService)
        sendShapeToBackUseCase = SendShapeToBackUseCaseImpl(shapeService: shapeService)
        deleteShapeUseCase = DeleteShapeUseCaseImpl(shapeService: shapeService)
        addTextUseCase = ValidationAsyncUseCaseDecorator(AddTextUseCaseImpl(textService: textService))
        duplicateTextUseCase = DuplicateTextUseCaseImpl(textService: textService)
        editTextUseCase = ValidationAsyncUseCaseDecorator(EditTextUseCaseImpl(textService: textService))
        moveTextUseCase = ValidationAsyncUseCaseDecorator(MoveTextUseCaseImpl(textService: textService))
        resizeTextUseCase = ValidationAsyncUseCaseDecorator(ResizeTextUseCaseImpl(textService: textService))
        setTextColorUseCase = ValidationAsyncUseCaseDecorator(SetTextColorUseCaseImpl(textService: textService))
        setTextFontSizeUseCase = ValidationAsyncUseCaseDecorator(SetTextFontSizeUseCaseImpl(textService: textService))
        bringTextToFrontUseCase = BringTextToFrontUseCaseImpl(textService: textService)
        sendTextToBackUseCase = SendTextToBackUseCaseImpl(textService: textService)
        deleteTextUseCase = DeleteTextUseCaseImpl(textService: textService)
        addImageUseCase = ValidationAsyncUseCaseDecorator(AddImageUseCaseImpl(imageService: imageService))
        moveImageUseCase = ValidationAsyncUseCaseDecorator(MoveImageUseCaseImpl(imageService: imageService))
        resizeImageUseCase = ValidationAsyncUseCaseDecorator(ResizeImageUseCaseImpl(imageService: imageService))
        deleteImageUseCase = DeleteImageUseCaseImpl(imageService: imageService)
        bringImageToFrontUseCase = BringImageToFrontUseCaseImpl(imageService: imageService)
        sendImageToBackUseCase = SendImageToBackUseCaseImpl(imageService: imageService)
        saveImageAssetUseCase = ValidationAsyncUseCaseDecorator(SaveImageAssetUseCaseImpl(imageService: imageService))
        deleteMarkdownImageUseCase = DeleteMarkdownImageUseCaseImpl(imageService: imageService)
        loadImageDataUseCase = LoadImageDataUseCaseImpl(imageService: imageService)
        sweepOrphanedImageAssetsUseCase = SweepOrphanedImageAssetsUseCaseImpl(imageService: imageService)
        reportImageLoadFailureUseCase = ReportImageLoadFailureUseCaseImpl(diagnostics: domain.diagnostics)
        reportPasteboardWriteFailureUseCase = ReportPasteboardWriteFailureUseCaseImpl(diagnostics: domain.diagnostics)
        addConnectorUseCase = ValidationAsyncUseCaseDecorator(AddConnectorUseCaseImpl(connectorService: connectorService))
        deleteConnectorUseCase = DeleteConnectorUseCaseImpl(connectorService: connectorService)
        setConnectorCapUseCase = ValidationAsyncUseCaseDecorator(SetConnectorCapUseCaseImpl(connectorService: connectorService))
        setConnectorRoutingUseCase = ValidationAsyncUseCaseDecorator(SetConnectorRoutingUseCaseImpl(connectorService: connectorService))
        setConnectorStrokeColorUseCase = ValidationAsyncUseCaseDecorator(SetConnectorStrokeColorUseCaseImpl(connectorService: connectorService))
        setConnectorStrokeWidthUseCase = ValidationAsyncUseCaseDecorator(SetConnectorStrokeWidthUseCaseImpl(connectorService: connectorService))
        setConnectorStyleUseCase = ValidationAsyncUseCaseDecorator(SetConnectorStyleUseCaseImpl(connectorService: connectorService))
        reconnectConnectorUseCase = ValidationAsyncUseCaseDecorator(ReconnectConnectorUseCaseImpl(connectorService: connectorService))
        setConnectorWaypointUseCase = ValidationAsyncUseCaseDecorator(SetConnectorWaypointUseCaseImpl(connectorService: connectorService))
        moveCanvasGroupUseCase = ValidationAsyncUseCaseDecorator(MoveCanvasGroupUseCaseImpl(groupService: canvasGroupService))
        deleteCanvasGroupUseCase = DeleteCanvasGroupUseCaseImpl(groupService: canvasGroupService)
        addLabelUseCase = ValidationAsyncUseCaseDecorator(AddLabelUseCaseImpl(labelService: labelService))
        editLabelUseCase = ValidationAsyncUseCaseDecorator(EditLabelUseCaseImpl(labelService: labelService))
        deleteLabelUseCase = DeleteLabelUseCaseImpl(labelService: labelService)
        toggleStickyLabelUseCase = ToggleStickyLabelUseCaseImpl(stickyService: stickyService)
        editBoardSettingsUseCase = EditBoardSettingsUseCaseImpl(boardManagement: boardManagement)
        editColumnAppearanceUseCase = ValidationAsyncUseCaseDecorator(
            EditColumnAppearanceUseCaseImpl(boardManagement: boardManagement)
        )
        loadBoardByIDUseCase = LoadBoardByIDUseCaseImpl(boardManagement: boardManagement)
        loadBoardTemplateUseCase = LoadBoardTemplateUseCaseImpl(boardManagement: boardManagement)
        editBoardTemplateUseCase = EditBoardTemplateUseCaseImpl(boardManagement: boardManagement)
        undoUseCase = UndoUseCaseImpl(boardManagement: boardManagement)
        recordMarkdownJournalUseCase = RecordMarkdownJournalUseCaseImpl(service: markdownJournalService)
        listMarkdownJournalUseCase = ListMarkdownJournalUseCaseImpl(service: markdownJournalService)
        clearMarkdownJournalUseCase = ClearMarkdownJournalUseCaseImpl(service: markdownJournalService)
    }

    /// The MCP server's entry point into the product. Bundles the Board/Canvas/Markdown use cases
    /// into the `KanvasMCPGateway` façade. Internal — the MCP executable reaches it through the
    /// public `KanvasMCP.makeGateway()`, keeping `Container` itself internal. Lives here (not on
    /// `PresentationContainer`) because the gateway is a sibling of Presentation that consumes only
    /// use cases, and because this container is `Sendable` — `KanvasMCP.makeGateway()` calls it off
    /// the main actor.
    func makeMCPGateway() -> KanvasMCPGateway {
        KanvasMCPGateway(
            loadActiveBoard: loadActiveBoardUseCase,
            loadBoardByID: loadBoardByIDUseCase,
            listBoards: listBoardsUseCase,
            addCard: addCardUseCase,
            editCard: editCardUseCase,
            moveCard: moveCardUseCase,
            deleteCard: deleteCardUseCase,
            addColumn: addColumnUseCase,
            renameColumn: renameColumnUseCase,
            deleteColumn: deleteColumnUseCase,
            editBoardSettings: editBoardSettingsUseCase,
            editColumnAppearance: editColumnAppearanceUseCase,
            loadCardDetail: loadCardDetailUseCase,
            addSticky: addStickyUseCase,
            editSticky: editStickyUseCase,
            moveSticky: moveStickyUseCase,
            setStickyFrame: setStickyFrameUseCase,
            deleteSticky: deleteStickyUseCase,
            promoteSticky: promoteStickyUseCase,
            demoteSticky: demoteStickyUseCase,
            addText: addTextUseCase,
            editText: editTextUseCase,
            moveText: moveTextUseCase,
            resizeText: resizeTextUseCase,
            setTextColor: setTextColorUseCase,
            setTextFontSize: setTextFontSizeUseCase,
            deleteText: deleteTextUseCase,
            addConnector: addConnectorUseCase,
            deleteConnector: deleteConnectorUseCase,
            setConnectorStyle: setConnectorStyleUseCase,
            reconnectConnector: reconnectConnectorUseCase,
            saveImageAsset: saveImageAssetUseCase,
            deleteMarkdownImage: deleteMarkdownImageUseCase
        )
    }
}
