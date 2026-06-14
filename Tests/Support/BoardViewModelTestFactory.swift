import Foundation
@testable import KanvasCore

// Shared `BoardViewModel` test factory + the generic use-case stubs it wires (ticket 3B1149F8).
//
// Every `BoardViewModelTests` file used to redefine its own private `makeBoardViewModel(...)` plus the
// same ~10 helper stubs (`StubLoadActiveBoard`, `BoardMutationStub<R>`, …). Adding one canvas use case meant
// editing all of them. They now share this single factory: each test overrides only the dependency it
// exercises via the matching default argument; everything else falls back to a no-op stub.

// MARK: - Fixture helpers

func stubBoardResponse(id: UUID = UUID()) -> BoardResponse {
    BoardResponse(
        board: BoardSummary(id: id, title: ""),
        columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
    )
}

func stubBoardListResponse() -> BoardListResponse {
    BoardListResponse(boards: [], activeBoardID: nil)
}

func stubBoardMutation(id: UUID = UUID()) -> BoardMutationResponse {
    BoardMutationResponse(board: stubBoardResponse(id: id), cardDetail: nil)
}

func stubBoardViewState(id: UUID = UUID()) -> BoardViewStateResponse {
    BoardViewStateResponse(board: stubBoardResponse(id: id), boardList: stubBoardListResponse(),
                           cardDetail: nil, matchedCardIDs: nil, matchedQuery: "")
}

// MARK: - Async wait helper

/// Polls `condition` on the main actor, yielding between checks so a fire-and-forget `Task` (e.g. a
/// fallback card-detail reload spawned by `refreshCardDetail`) can run, until it holds or `maxYields`
/// is exhausted. Returns whether it held — a test asserts on that instead of a blind fixed-count wait,
/// so the wait ends as soon as the expected state is reached and a regression surfaces as `false`
/// rather than a flaky pass.
@MainActor
func waitUntil(_ condition: () -> Bool, maxYields: Int = 100) async -> Bool {
    for _ in 0..<maxYields {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

// MARK: - Generic stubs

final class StubLoadActiveBoard: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: LoadActiveBoardRequest) async throws -> BoardResponse { stubBoardResponse() }
}

final class StubLoadBoardViewState: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: LoadBoardViewStateRequest) async throws -> BoardViewStateResponse { stubBoardViewState() }
}

final class StubLoadCardDetail: LoadCardDetailUseCase, @unchecked Sendable {
    func execute(cardID: UUID) async throws -> CardDetailResponse? { nil }
}

final class StubSearchCards: SearchCardsUseCase, @unchecked Sendable {
    func execute(query: String) async throws -> Set<UUID> { [] }
}

final class StubListBoards: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse { stubBoardListResponse() }
}

/// Generic stub for every `… -> BoardResponse` use case. Since those protocols are `any`-typealiases,
/// one class cannot conform to all of them; a generic struct constrained to each request type can.
struct BoardResponseStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { stubBoardResponse() }
}

/// Generic stub for every `… -> BoardMutationResponse` use case.
struct BoardMutationStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse { stubBoardMutation() }
}

final class StubRenameBoard: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: RenameBoardRequest) async throws -> BoardListResponse { stubBoardListResponse() }
}

final class StubAddCard: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: stubBoardResponse())
    }
}

final class StubLoadImageData: LoadImageDataUseCase, @unchecked Sendable {
    func execute(assetID: UUID) async throws -> Data { Data() }
}

struct StubSaveImageAsset: AsyncUseCase, Sendable {
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        SaveImageAssetResponse(assetID: UUID())
    }
}

final class StubSweepOrphanedImageAssets: SweepOrphanedImageAssetsUseCase, Sendable {
    func execute() async throws {}
}

final class StubUndo: AsyncUseCase, @unchecked Sendable {
    func execute(_ request: UndoRequest) async throws -> UndoResponse { .nothingToUndo }
}

// MARK: - Factory

/// Constructs a `BoardViewModel` with every dependency stubbed. Each parameter defaults to a no-op
/// stub; a test overrides only the slot it exercises (e.g. `makeBoardViewModel(addShape: mock)`).
@MainActor
func makeBoardViewModel(
    loadBoardViewState: LoadBoardViewStateUseCase = StubLoadBoardViewState(),
    loadCardDetail: any LoadCardDetailUseCase = StubLoadCardDetail(),
    search: any SearchCardsUseCase = StubSearchCards(),
    addShape: AddShapeUseCase = BoardMutationStub<AddShapeRequest>(),
    addText: AddTextUseCase = BoardMutationStub<AddTextRequest>(),
    duplicateText: DuplicateTextUseCase = BoardMutationStub<DuplicateTextRequest>(),
    deleteSticky: DeleteStickyUseCase = BoardMutationStub<DeleteStickyRequest>(),
    editSticky: EditStickyUseCase = BoardMutationStub<EditStickyRequest>(),
    editCard: EditCardUseCase = BoardMutationStub<EditCardRequest>(),
    undo: UndoUseCase = StubUndo(),
    reportPasteboardWriteFailure: any ReportPasteboardWriteFailureUseCase = StubReportPasteboardWriteFailure(),
    moveGroup: MoveCanvasGroupUseCase = BoardMutationStub<MoveCanvasGroupRequest>(),
    deleteGroup: DeleteCanvasGroupUseCase = BoardMutationStub<DeleteCanvasGroupRequest>(),
    loadData: any LoadImageDataUseCase = StubLoadImageData(),
    sweepOrphans: any SweepOrphanedImageAssetsUseCase = StubSweepOrphanedImageAssets(),
    journalList: any ListMarkdownJournalUseCase = StubListMarkdownJournal()
) -> BoardViewModel {
    BoardViewModel(
        loadBoardViewState: loadBoardViewState,
        loadCardDetail: loadCardDetail,
        undo: undo,
        reportPasteboardWriteFailure: reportPasteboardWriteFailure,
        management: stubManagementUseCases(search: search),
        kanban: stubKanbanUseCases(editCard: editCard),
        sticky: stubStickyUseCases(editSticky: editSticky, deleteSticky: deleteSticky),
        shape: stubShapeUseCases(addShape: addShape),
        text: stubTextUseCases(addText: addText, duplicateText: duplicateText),
        image: stubImageUseCases(loadData: loadData, sweepOrphans: sweepOrphans),
        connector: stubConnectorUseCases(),
        group: BoardGroupUseCases(move: moveGroup, delete: deleteGroup),
        label: stubLabelUseCases(),
        markdownJournal: stubMarkdownJournalUseCases(journalList: journalList)
    )
}

// MARK: - Per-bundle factories
//
// Each `Board*UseCases` bundle is assembled by its own helper so the top-level `makeBoardViewModel`
// body stays under `function_body_length` (no disable). A helper takes only the slots a test ever
// overrides; the rest fall back to no-op stubs.

private func stubManagementUseCases(search: any SearchCardsUseCase) -> BoardManagementUseCases {
    BoardManagementUseCases(
        list: StubListBoards(),
        add: BoardResponseStub<AddBoardRequest>(),
        switchBoard: BoardResponseStub<SwitchBoardRequest>(),
        rename: StubRenameBoard(),
        delete: BoardResponseStub<DeleteBoardRequest>(),
        search: search
    )
}

private func stubKanbanUseCases(editCard: EditCardUseCase) -> BoardKanbanUseCases {
    BoardKanbanUseCases(
        addColumn: BoardResponseStub<AddColumnRequest>(),
        renameColumn: BoardResponseStub<RenameColumnRequest>(),
        setCompletionColumn: BoardResponseStub<SetCompletionColumnRequest>(),
        reorderColumn: BoardResponseStub<ReorderColumnRequest>(),
        deleteColumn: BoardResponseStub<DeleteColumnRequest>(),
        addCard: StubAddCard(),
        editCard: editCard,
        moveCard: BoardMutationStub<MoveCardRequest>(),
        deleteCard: BoardResponseStub<DeleteCardRequest>()
    )
}

private func stubStickyUseCases(
    editSticky: EditStickyUseCase,
    deleteSticky: DeleteStickyUseCase
) -> BoardStickyUseCases {
    BoardStickyUseCases(
        add: BoardMutationStub<AddStickyRequest>(),
        duplicate: BoardMutationStub<DuplicateStickyRequest>(),
        edit: editSticky,
        setTextColor: BoardMutationStub<SetStickyTextColorRequest>(),
        setFillColor: BoardMutationStub<SetStickyFillColorRequest>(),
        setFontSize: BoardMutationStub<SetStickyFontSizeRequest>(),
        move: BoardMutationStub<MoveStickyRequest>(),
        setFrame: BoardMutationStub<SetStickyFrameRequest>(),
        bringToFront: BoardMutationStub<BringStickyToFrontRequest>(),
        sendToBack: BoardMutationStub<SendStickyToBackRequest>(),
        promote: BoardMutationStub<PromoteStickyRequest>(),
        demote: BoardMutationStub<DemoteStickyRequest>(),
        delete: deleteSticky
    )
}

private func stubShapeUseCases(addShape: AddShapeUseCase) -> BoardShapeUseCases {
    BoardShapeUseCases(
        add: addShape,
        move: BoardMutationStub<MoveShapeRequest>(),
        resize: BoardMutationStub<ResizeShapeRequest>(),
        setStrokeColor: BoardMutationStub<SetShapeStrokeColorRequest>(),
        setFillColor: BoardMutationStub<SetShapeFillColorRequest>(),
        setStrokeWidth: BoardMutationStub<SetShapeStrokeWidthRequest>(),
        bringToFront: BoardMutationStub<BringShapeToFrontRequest>(),
        sendToBack: BoardMutationStub<SendShapeToBackRequest>(),
        delete: BoardMutationStub<DeleteShapeRequest>()
    )
}

private func stubTextUseCases(
    addText: AddTextUseCase,
    duplicateText: DuplicateTextUseCase
) -> BoardTextUseCases {
    BoardTextUseCases(
        add: addText,
        duplicate: duplicateText,
        edit: BoardMutationStub<EditTextRequest>(),
        move: BoardMutationStub<MoveTextRequest>(),
        resize: BoardMutationStub<ResizeTextRequest>(),
        setColor: BoardMutationStub<SetTextColorRequest>(),
        setFontSize: BoardMutationStub<SetTextFontSizeRequest>(),
        bringToFront: BoardMutationStub<BringTextToFrontRequest>(),
        sendToBack: BoardMutationStub<SendTextToBackRequest>(),
        delete: BoardMutationStub<DeleteTextRequest>()
    )
}

private func stubImageUseCases(
    loadData: any LoadImageDataUseCase,
    sweepOrphans: any SweepOrphanedImageAssetsUseCase
) -> BoardImageUseCases {
    BoardImageUseCases(
        add: BoardMutationStub<AddImageRequest>(),
        move: BoardMutationStub<MoveImageRequest>(),
        resize: BoardMutationStub<ResizeImageRequest>(),
        delete: BoardMutationStub<DeleteImageRequest>(),
        bringToFront: BoardMutationStub<BringImageToFrontRequest>(),
        sendToBack: BoardMutationStub<SendImageToBackRequest>(),
        saveAsset: StubSaveImageAsset(),
        deleteMarkdownImage: BoardMutationStub<DeleteMarkdownImageRequest>(),
        loadData: loadData,
        sweepOrphans: sweepOrphans,
        reportLoadFailure: StubReportImageLoadFailure()
    )
}

private func stubConnectorUseCases() -> BoardConnectorUseCases {
    BoardConnectorUseCases(
        add: BoardMutationStub<AddConnectorRequest>(),
        delete: BoardMutationStub<DeleteConnectorRequest>(),
        setCap: BoardMutationStub<SetConnectorCapRequest>(),
        setRouting: BoardMutationStub<SetConnectorRoutingRequest>(),
        setStrokeColor: BoardMutationStub<SetConnectorStrokeColorRequest>(),
        setStrokeWidth: BoardMutationStub<SetConnectorStrokeWidthRequest>(),
        reconnect: BoardMutationStub<ReconnectConnectorRequest>(),
        setWaypoint: BoardMutationStub<SetConnectorWaypointRequest>()
    )
}

private func stubLabelUseCases() -> BoardLabelUseCases {
    BoardLabelUseCases(
        add: BoardResponseStub<AddLabelRequest>(),
        edit: BoardResponseStub<EditLabelRequest>(),
        delete: BoardResponseStub<DeleteLabelRequest>(),
        toggle: BoardMutationStub<ToggleStickyLabelRequest>()
    )
}

private func stubMarkdownJournalUseCases(
    journalList: any ListMarkdownJournalUseCase
) -> BoardMarkdownJournalUseCases {
    BoardMarkdownJournalUseCases(
        record: StubRecordMarkdownJournal(),
        list: journalList,
        clear: StubClearMarkdownJournal()
    )
}
