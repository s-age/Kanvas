import XCTest
@testable import KanvasCore

/// The `board_*` write echoes are deliberately **token-light** (the fix for a one-field title edit
/// returning the whole board — hundreds of card summaries, ~22k tokens on a busy board):
///
/// - `editCard` / `moveCard` echo only the affected card plus its column (`CardEchoOut`),
/// - `deleteCard` echoes `{deletedID}`,
/// - the column ops echo the column list **without** the card summaries (`BoardColumnsOut`).
///
/// These tests pin that none of them re-emit sibling card summaries.
final class KanvasMCPBoardEchoTests: XCTestCase {

    private let cardID = UUID()
    private let columnID = UUID()

    // MARK: - editCard / moveCard → single-card echo

    func testEditCard_echoesTheEditedCardWithItsColumn() async throws {
        let sut = makeGateway(editCard: MutationStub<EditCardRequest>(board: boardWithCard(title: "Edited")))
        let json = try await sut.editCard(cardID: cardID.uuidString, title: "Edited")
        XCTAssertTrue(json.contains(cardID.uuidString))
        XCTAssertTrue(json.contains(columnID.uuidString))
        XCTAssertTrue(json.contains("Edited"))
    }

    func testEditCard_omitsSiblingCardSummaries() async throws {
        let sut = makeGateway(editCard: MutationStub<EditCardRequest>(board: boardWithCard(title: "Edited")))
        let json = try await sut.editCard(cardID: cardID.uuidString, title: "Edited")
        XCTAssertFalse(json.contains("SIBLING_CARD"))  // token-light: never the whole-board dump
    }

    func testEditCard_cardAbsentFromResult_throwsNotFoundCard() async throws {
        // The refreshed board carries some other card, not the requested one (a concurrent foreign
        // delete between the mutation and this read).
        let sut = makeGateway(editCard: MutationStub<EditCardRequest>(board: boardWithCard(cardID: UUID(), title: "x")))
        do {
            _ = try await sut.editCard(cardID: cardID.uuidString, title: "Edited")
            XCTFail("Expected notFound")
        } catch let error as KanvasMCPError {
            if case .notFound(let kind, _) = error { XCTAssertEqual(kind, "Card") } else {
                XCTFail("Expected notFound(Card), got \(error)")
            }
        }
    }

    func testMoveCard_echoesTheMovedCardWithItsColumn() async throws {
        let sut = makeGateway(moveCard: MutationStub<MoveCardRequest>(board: boardWithCard(title: "Moved")))
        let json = try await sut.moveCard(
            cardID: cardID.uuidString, toColumnID: columnID.uuidString, beforeCardID: nil
        )
        XCTAssertTrue(json.contains(columnID.uuidString))
        XCTAssertFalse(json.contains("SIBLING_CARD"))
    }

    // MARK: - deleteCard → {deletedID}

    func testDeleteCard_echoesOnlyTheDeletedID() async throws {
        let sut = makeGateway(deleteCard: BoardStub<DeleteCardRequest>(board: boardWithCard(title: "Gone")))
        let json = try await sut.deleteCard(cardID: cardID.uuidString)
        XCTAssertTrue(json.contains("deletedID"))
        XCTAssertTrue(json.contains(cardID.uuidString))
        XCTAssertFalse(json.contains("SIBLING_CARD"))
    }

    // MARK: - column ops → BoardColumnsOut (columns, no card summaries)

    func testRenameColumn_echoesColumnsWithCardCountButNoCardSummaries() async throws {
        let sut = makeGateway(renameColumn: BoardStub<RenameColumnRequest>(board: boardWithCard(title: "T")))
        let json = try await sut.renameColumn(columnID: columnID.uuidString, title: "Renamed")
        XCTAssertTrue(json.contains("cardCount"))
        XCTAssertTrue(json.contains(columnID.uuidString))
        XCTAssertFalse(json.contains("SIBLING_CARD"))  // card summaries are dropped
    }

    func testEditColumnAppearance_echoesColumnsWithoutCardSummaries() async throws {
        let sut = makeGateway(
            editColumnAppearance: BoardStub<EditColumnAppearanceRequest>(board: boardWithCard(title: "T"))
        )
        let json = try await sut.editColumnAppearance(
            columnID: columnID.uuidString,
            appearance: ColumnAppearanceEdit(
                headerColorHex: "3478F6", headerTextColorHex: nil, bodyColorHex: nil,
                headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil,
                isCompletionColumn: nil
            )
        )
        XCTAssertTrue(json.contains("cardCount"))
        XCTAssertFalse(json.contains("SIBLING_CARD"))
    }
}

// MARK: - Fixtures

extension KanvasMCPBoardEchoTests {

    /// A board whose single column holds the test card plus one sibling — the sibling's title
    /// (`SIBLING_CARD`) is the canary the echoes must NOT leak.
    private func boardWithCard(cardID: UUID? = nil, title: String) -> BoardResponse {
        let card = CardSummary(
            id: cardID ?? self.cardID, title: title, status: .todo, hasSchedule: false, labelCount: 0
        )
        let sibling = CardSummary(
            id: UUID(), title: "SIBLING_CARD", status: .todo, hasSchedule: false, labelCount: 0
        )
        let column = ColumnResponse(
            id: columnID, title: "Column", sortIndex: 0, isCompletionColumn: false,
            headerColorHex: nil, headerTextColorHex: nil, bodyColorHex: nil,
            headerBorderColorHex: nil, bodyBorderColorHex: nil, indicatorColorHex: nil,
            cards: [card, sibling]
        )
        return BoardResponse(
            board: BoardSummary(id: UUID(), title: ""),
            columns: [column], labels: [], settings: SettingsTestFixtures.defaultSettings
        )
    }
}

// MARK: - Configurable stubs

private struct MutationStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    let board: BoardResponse
    func execute(_ request: R) async throws -> BoardMutationResponse {
        BoardMutationResponse(board: board, cardDetail: nil)
    }
}

private struct BoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    let board: BoardResponse
    func execute(_ request: R) async throws -> BoardResponse { board }
}

// MARK: - Default stubs + gateway factory

private func emptyBoard() -> BoardResponse {
    BoardResponse(
        board: BoardSummary(id: UUID(), title: ""),
        columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
    )
}

private struct DefaultMutStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse {
        BoardMutationResponse(board: emptyBoard(), cardDetail: nil)
    }
}

private struct DefaultBoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { emptyBoard() }
}

private struct DefaultListStub: AsyncUseCase, Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        BoardListResponse(boards: [], activeBoardID: nil)
    }
}

private struct DefaultAddCardStub: AsyncUseCase, Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: emptyBoard())
    }
}

private struct DefaultSaveImageStub: AsyncUseCase, Sendable {
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        SaveImageAssetResponse(assetID: UUID())
    }
}

private struct DefaultLoadCardDetailStub: LoadCardDetailUseCase, Sendable {
    func execute(cardID: UUID) async throws -> CardDetailResponse? { nil }
}

private func makeGateway(
    editCard: EditCardUseCase = DefaultMutStub<EditCardRequest>(),
    moveCard: MoveCardUseCase = DefaultMutStub<MoveCardRequest>(),
    deleteCard: DeleteCardUseCase = DefaultBoardStub<DeleteCardRequest>(),
    addColumn: AddColumnUseCase = DefaultBoardStub<AddColumnRequest>(),
    renameColumn: RenameColumnUseCase = DefaultBoardStub<RenameColumnRequest>(),
    deleteColumn: DeleteColumnUseCase = DefaultBoardStub<DeleteColumnRequest>(),
    editColumnAppearance: EditColumnAppearanceUseCase = DefaultBoardStub<EditColumnAppearanceRequest>()
) -> KanvasMCPGateway {
    KanvasMCPGateway(
        loadActiveBoard: DefaultBoardStub<LoadActiveBoardRequest>(),
        loadBoardByID: DefaultBoardStub<LoadBoardByIDRequest>(),
        listBoards: DefaultListStub(),
        addCard: DefaultAddCardStub(),
        editCard: editCard,
        moveCard: moveCard,
        deleteCard: deleteCard,
        addColumn: addColumn,
        renameColumn: renameColumn,
        deleteColumn: deleteColumn,
        editBoardSettings: DefaultBoardStub<EditBoardSettingsRequest>(),
        editColumnAppearance: editColumnAppearance,
        loadCardDetail: DefaultLoadCardDetailStub(),
        addSticky: DefaultMutStub<AddStickyRequest>(),
        editSticky: DefaultMutStub<EditStickyRequest>(),
        moveSticky: DefaultMutStub<MoveStickyRequest>(),
        setStickyFrame: DefaultMutStub<SetStickyFrameRequest>(),
        deleteSticky: DefaultMutStub<DeleteStickyRequest>(),
        promoteSticky: DefaultMutStub<PromoteStickyRequest>(),
        demoteSticky: DefaultMutStub<DemoteStickyRequest>(),
        addText: DefaultMutStub<AddTextRequest>(),
        editText: DefaultMutStub<EditTextRequest>(),
        moveText: DefaultMutStub<MoveTextRequest>(),
        resizeText: DefaultMutStub<ResizeTextRequest>(),
        setTextColor: DefaultMutStub<SetTextColorRequest>(),
        setTextFontSize: DefaultMutStub<SetTextFontSizeRequest>(),
        deleteText: DefaultMutStub<DeleteTextRequest>(),
        addConnector: DefaultMutStub<AddConnectorRequest>(),
        deleteConnector: DefaultMutStub<DeleteConnectorRequest>(),
        setConnectorStyle: DefaultMutStub<SetConnectorStyleRequest>(),
        reconnectConnector: DefaultMutStub<ReconnectConnectorRequest>(),
        saveImageAsset: DefaultSaveImageStub(),
        deleteMarkdownImage: DefaultMutStub<DeleteMarkdownImageRequest>()
    )
}
