import XCTest
@testable import KanvasCore

/// `KanvasMCPGateway` free-text CRUD: verifies the gateway wires the tool arguments into the right
/// requests and echoes the card's canvas. `editText` applies content + optional style as separate
/// mutations, so the colour/font-size setters are exercised only when their argument is present.
final class KanvasMCPTextTests: XCTestCase {

    private let cardID = UUID()
    private let textID = UUID()

    func testAddText_forwardsContentAndFrame() async throws {
        let add = CaptureAddText()
        let sut = makeTextGateway(addText: add)

        _ = try await sut.addText(
            cardID: cardID.uuidString, content: "hello",
            frame: StickyFrame(x: 5, y: 6, width: 200, height: 80)
        )

        XCTAssertEqual(add.lastRequest?.content, "hello")
        XCTAssertEqual(add.lastRequest?.positionX, 5)
        XCTAssertEqual(add.lastRequest?.width, 200)
    }

    func testEditText_contentOnly_skipsStyleSetters() async throws {
        let edit = CaptureEditText()
        let setColor = CaptureSetTextColor()
        let setFont = CaptureSetTextFontSize()
        let sut = makeTextGateway(editText: edit, setTextColor: setColor, setTextFontSize: setFont)

        _ = try await sut.editText(
            cardID: cardID.uuidString, textID: textID.uuidString, content: "x",
            style: TextStyleEdit(colorHex: nil, fontSize: nil)
        )

        XCTAssertEqual(edit.callCount, 1)
        XCTAssertEqual(setColor.callCount, 0)
        XCTAssertEqual(setFont.callCount, 0)
    }

    func testEditText_withStyle_appliesColorAndFontSize() async throws {
        let setColor = CaptureSetTextColor()
        let setFont = CaptureSetTextFontSize()
        let sut = makeTextGateway(setTextColor: setColor, setTextFontSize: setFont)

        _ = try await sut.editText(
            cardID: cardID.uuidString, textID: textID.uuidString, content: "x",
            style: TextStyleEdit(colorHex: "AABBCC", fontSize: 20)
        )

        XCTAssertEqual(setColor.lastColorHex, "AABBCC")
        XCTAssertEqual(setFont.lastFontSize, 20)
    }

    func testEditText_blankContentWithStyle_skipsStyleSetters() async throws {
        // A blank body auto-deletes the text (TextService.editing), so the style setters must be
        // skipped — restyling a just-deleted text would throw notFound on the missing id.
        let setColor = CaptureSetTextColor()
        let setFont = CaptureSetTextFontSize()
        let sut = makeTextGateway(setTextColor: setColor, setTextFontSize: setFont)

        _ = try await sut.editText(
            cardID: cardID.uuidString, textID: textID.uuidString, content: "   ",
            style: TextStyleEdit(colorHex: "AABBCC", fontSize: 20)
        )

        XCTAssertEqual(setColor.callCount, 0)
    }

    func testEditText_blankContentWithStyle_skipsFontSizeSetter() async throws {
        let setColor = CaptureSetTextColor()
        let setFont = CaptureSetTextFontSize()
        let sut = makeTextGateway(setTextColor: setColor, setTextFontSize: setFont)

        _ = try await sut.editText(
            cardID: cardID.uuidString, textID: textID.uuidString, content: "",
            style: TextStyleEdit(colorHex: "AABBCC", fontSize: 20)
        )

        XCTAssertEqual(setFont.callCount, 0)
    }

    func testDeleteText_forwardsTextAndCardID() async throws {
        let delete = CaptureDeleteText()
        let sut = makeTextGateway(deleteText: delete)

        _ = try await sut.deleteText(cardID: cardID.uuidString, textID: textID.uuidString)

        XCTAssertEqual(delete.lastRequest?.textID, textID)
        XCTAssertEqual(delete.lastRequest?.cardID, cardID)
    }
}

// MARK: - Capture stubs

private final class CaptureAddText: AsyncUseCase, @unchecked Sendable {
    private(set) var lastRequest: AddTextRequest?
    func execute(_ request: AddTextRequest) async throws -> BoardMutationResponse {
        lastRequest = request
        return textBoardMutation()
    }
}

private final class CaptureEditText: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    func execute(_ request: EditTextRequest) async throws -> BoardMutationResponse {
        callCount += 1
        return textBoardMutation()
    }
}

private final class CaptureSetTextColor: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastColorHex: String?
    func execute(_ request: SetTextColorRequest) async throws -> BoardMutationResponse {
        callCount += 1
        lastColorHex = request.colorHex
        return textBoardMutation()
    }
}

private final class CaptureSetTextFontSize: AsyncUseCase, @unchecked Sendable {
    private(set) var callCount = 0
    private(set) var lastFontSize: Double?
    func execute(_ request: SetTextFontSizeRequest) async throws -> BoardMutationResponse {
        callCount += 1
        lastFontSize = request.fontSize
        return textBoardMutation()
    }
}

private final class CaptureDeleteText: AsyncUseCase, @unchecked Sendable {
    private(set) var lastRequest: DeleteTextRequest?
    func execute(_ request: DeleteTextRequest) async throws -> BoardMutationResponse {
        lastRequest = request
        return textBoardMutation()
    }
}

private struct TextMutStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse { textBoardMutation() }
}

private struct TextBoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { textBoardResponse() }
}

private struct TextListBoardsStub: AsyncUseCase, Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        BoardListResponse(boards: [], activeBoardID: nil)
    }
}

private struct TextAddCardStub: AsyncUseCase, Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: textBoardResponse())
    }
}

private struct TextSaveImageAssetStub: AsyncUseCase, Sendable {
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        SaveImageAssetResponse(assetID: UUID())
    }
}

private final class TextLoadCardDetailStub: LoadCardDetailUseCase, @unchecked Sendable {
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        CardDetailResponse(
            id: cardID, title: "Card", markdownContent: "",
            status: .todo, columnTitle: "To Do",
            schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
            stickies: [], shapes: [], images: [], texts: [], connectors: []
        )
    }
}

private func textBoardResponse() -> BoardResponse {
    BoardResponse(board: BoardSummary(id: UUID(), title: ""), columns: [], labels: [],
                  settings: SettingsTestFixtures.defaultSettings)
}

private func textBoardMutation() -> BoardMutationResponse {
    BoardMutationResponse(board: textBoardResponse(), cardDetail: nil)
}

private func makeTextGateway(
    addText: AddTextUseCase = TextMutStub<AddTextRequest>(),
    editText: EditTextUseCase = TextMutStub<EditTextRequest>(),
    setTextColor: SetTextColorUseCase = TextMutStub<SetTextColorRequest>(),
    setTextFontSize: SetTextFontSizeUseCase = TextMutStub<SetTextFontSizeRequest>(),
    deleteText: DeleteTextUseCase = TextMutStub<DeleteTextRequest>()
) -> KanvasMCPGateway {
    KanvasMCPGateway(
        loadActiveBoard: TextBoardStub<LoadActiveBoardRequest>(),
        loadBoardByID: TextBoardStub<LoadBoardByIDRequest>(),
        listBoards: TextListBoardsStub(),
        addCard: TextAddCardStub(),
        editCard: TextMutStub<EditCardRequest>(),
        moveCard: TextMutStub<MoveCardRequest>(),
        deleteCard: TextBoardStub<DeleteCardRequest>(),
        addColumn: TextBoardStub<AddColumnRequest>(),
        renameColumn: TextBoardStub<RenameColumnRequest>(),
        deleteColumn: TextBoardStub<DeleteColumnRequest>(),
        editBoardSettings: TextBoardStub<EditBoardSettingsRequest>(),
        editColumnAppearance: TextBoardStub<EditColumnAppearanceRequest>(),
        loadCardDetail: TextLoadCardDetailStub(),
        addSticky: TextMutStub<AddStickyRequest>(),
        editSticky: TextMutStub<EditStickyRequest>(),
        moveSticky: TextMutStub<MoveStickyRequest>(),
        setStickyFrame: TextMutStub<SetStickyFrameRequest>(),
        deleteSticky: TextMutStub<DeleteStickyRequest>(),
        promoteSticky: TextMutStub<PromoteStickyRequest>(),
        demoteSticky: TextMutStub<DemoteStickyRequest>(),
        addText: addText,
        editText: editText,
        moveText: TextMutStub<MoveTextRequest>(),
        resizeText: TextMutStub<ResizeTextRequest>(),
        setTextColor: setTextColor,
        setTextFontSize: setTextFontSize,
        deleteText: deleteText,
        addConnector: TextMutStub<AddConnectorRequest>(),
        deleteConnector: TextMutStub<DeleteConnectorRequest>(),
        setConnectorStyle: TextMutStub<SetConnectorStyleRequest>(),
        reconnectConnector: TextMutStub<ReconnectConnectorRequest>(),
        saveImageAsset: TextSaveImageAssetStub(),
        deleteMarkdownImage: TextMutStub<DeleteMarkdownImageRequest>()
    )
}
