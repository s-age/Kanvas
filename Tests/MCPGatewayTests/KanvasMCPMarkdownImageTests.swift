import XCTest
@testable import KanvasCore

/// `KanvasMCPGateway.addMarkdownImage` (ticket 71A2D7D4): the MCP equivalent of the editor's
/// drag-drop / ⌘V image import. It must decode the base64 PNG bytes, mint an asset via the shared
/// `SaveImageAssetUseCase`, and append a `kanvas-asset://<id>` reference to the card's existing
/// Markdown body via `editCard` — so the inline renderer and orphan-GC scan see it exactly as a
/// dropped image. A non-base64 argument is a loud `badBase64` failure, and a payload missing the PNG
/// signature is a loud `notPNG` failure — neither is a silent no-op.
final class KanvasMCPMarkdownImageTests: XCTestCase {

    private let cardID = UUID()

    /// The 8-byte PNG file signature, with a trailing byte so a stored asset has real content.
    private static func pngBytes(_ trailing: [UInt8] = [0x00]) -> Data {
        Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + trailing)
    }

    func testAddMarkdownImage_savesAssetAndAppendsReferenceToExistingBody() async throws {
        let assetID = UUID()
        let spySave = SpySaveImageAsset(assetID: assetID)
        let spyEdit = SpyEditCard()
        let load = StubLoadCardDetailWithBody(markdown: "Existing notes")
        let sut = makeGateway(editCard: spyEdit, loadCardDetail: load, saveImageAsset: spySave)
        let pngBase64 = Self.pngBytes().base64EncodedString()

        _ = try await sut.addMarkdownImage(cardID: cardID.uuidString, imageBase64: pngBase64)

        let expectedReference = MarkdownImageReference.markdown(for: assetID)
        // Own-line append mirroring the editor drop path's "\n<reference>\n" (single newlines).
        XCTAssertEqual(spyEdit.lastMarkdownContent, "Existing notes\n" + expectedReference + "\n")
    }

    func testAddMarkdownImage_decodesBase64BeforeSaving() async throws {
        let spySave = SpySaveImageAsset(assetID: UUID())
        let sut = makeGateway(editCard: SpyEditCard(), loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: spySave)
        let bytes = Self.pngBytes([0x01, 0x02, 0x03, 0x04])

        _ = try await sut.addMarkdownImage(cardID: cardID.uuidString,
                                           imageBase64: bytes.base64EncodedString())

        XCTAssertEqual(spySave.lastImageData, bytes)
    }

    func testAddMarkdownImage_emptyBody_appendsReferenceWithNoLeadingSeparator() async throws {
        let assetID = UUID()
        let spyEdit = SpyEditCard()
        let sut = makeGateway(editCard: spyEdit, loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: SpySaveImageAsset(assetID: assetID))
        let pngBase64 = Self.pngBytes().base64EncodedString()

        _ = try await sut.addMarkdownImage(cardID: cardID.uuidString, imageBase64: pngBase64)

        // No leading newline on an empty body; trailing newline keeps the image on its own line.
        XCTAssertEqual(spyEdit.lastMarkdownContent, MarkdownImageReference.markdown(for: assetID) + "\n")
    }

    func testAddMarkdownImage_invalidBase64_throwsBadBase64() async throws {
        let sut = makeGateway(editCard: SpyEditCard(), loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: SpySaveImageAsset(assetID: UUID()))

        do {
            _ = try await sut.addMarkdownImage(cardID: cardID.uuidString, imageBase64: "not base64!!!")
            XCTFail("Expected badBase64 to be thrown")
        } catch let error as KanvasMCPError {
            guard case .badBase64 = error else {
                return XCTFail("Expected .badBase64, got \(error)")
            }
        }
    }

    func testAddMarkdownImage_nonPNGBytes_throwsNotPNG() async throws {
        let spySave = SpySaveImageAsset(assetID: UUID())
        let sut = makeGateway(editCard: SpyEditCard(), loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: spySave)
        // Valid base64, but a JPEG SOI marker — not a PNG. Must reject before saving the asset.
        let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46])

        do {
            _ = try await sut.addMarkdownImage(cardID: cardID.uuidString,
                                               imageBase64: jpegBytes.base64EncodedString())
            XCTFail("Expected notPNG to be thrown")
        } catch let error as KanvasMCPError {
            guard case .notPNG = error else {
                return XCTFail("Expected .notPNG, got \(error)")
            }
        }
        XCTAssertNil(spySave.lastImageData, "A non-PNG payload must be rejected before the asset is saved")
    }

    // MARK: - Early size reject (ticket F20D872C)

    func testAddMarkdownImage_overCapBase64_throwsImageTooLargeBeforeSaving() async throws {
        let spySave = SpySaveImageAsset(assetID: UUID())
        let sut = makeGateway(editCard: SpyEditCard(), loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: spySave)
        // A base64 string whose minimum decoded size already exceeds the 32MB cap — long enough to
        // trip the length pre-check, without decoding to real PNG bytes (the guard fires first).
        let cap = ContentSizeValidation.maxImageByteCount
        let overCap = String(repeating: "A", count: (cap / 3 + 1) * 4 + 4)

        do {
            _ = try await sut.addMarkdownImage(cardID: cardID.uuidString, imageBase64: overCap)
            XCTFail("Expected imageTooLarge to be thrown")
        } catch let error as KanvasMCPError {
            guard case .imageTooLarge = error else {
                return XCTFail("Expected .imageTooLarge, got \(error)")
            }
        }
        XCTAssertNil(spySave.lastImageData, "An over-cap payload must be rejected before the asset is saved")
    }

    func testExceedsImageByteCap_atOrBelowCapLength_isFalse() {
        // A length whose *maximum* decoded size equals the cap exactly is accepted — its minimum
        // decode is below the cap, so the exact byte check downstream is the authority.
        let lengthForCap = (ContentSizeValidation.maxImageByteCount / 3) * 4
        XCTAssertFalse(MCPImageValidation.exceedsImageByteCap(base64Length: lengthForCap))
    }

    func testExceedsImageByteCap_atCapBoundaryLength_isFalse() {
        // The 1–2 byte window at exactly the cap: this length's *maximum* decode is cap + 1, but with
        // 1 padding char it decodes to exactly the cap (accepted) and with 2 to cap - 1 (accepted).
        // Because some valid padding decodes at/under the cap, the guard must NOT reject it — the
        // exact byte check downstream is the authority (ticket F20D872C invariant: never reject an
        // input the UseCase would accept).
        let cap = ContentSizeValidation.maxImageByteCount
        let lengthAtCapBoundary = (cap / 3 + 1) * 4
        // Sanity: the old max-decode formula would have rejected this.
        XCTAssertGreaterThan((lengthAtCapBoundary / 4) * 3, cap)
        XCTAssertFalse(MCPImageValidation.exceedsImageByteCap(base64Length: lengthAtCapBoundary))
    }

    func testExceedsImageByteCap_overCapLength_isTrue() {
        // A length whose *minimum* decoded size (max-decode minus 2 padding) still exceeds the cap —
        // every valid padding decodes over-cap, so the guard rejects.
        let lengthOverCap = (ContentSizeValidation.maxImageByteCount / 3 + 1) * 4 + 4
        XCTAssertTrue(MCPImageValidation.exceedsImageByteCap(base64Length: lengthOverCap))
    }

    // MARK: - deleteMarkdownImage (ticket 2A2784BE)

    func testDeleteMarkdownImage_passesCardAndAssetIDsToTheUseCase() async throws {
        let assetID = UUID()
        let spy = SpyDeleteMarkdownImage(refreshedBody: "")
        let sut = makeGateway(editCard: SpyEditCard(),
                              loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: SpySaveImageAsset(assetID: UUID()),
                              deleteMarkdownImage: spy)

        _ = try await sut.deleteMarkdownImage(cardID: cardID.uuidString, assetID: assetID.uuidString)

        XCTAssertEqual(spy.lastRequest?.cardID, cardID)
        XCTAssertEqual(spy.lastRequest?.assetID, assetID)
    }

    func testDeleteMarkdownImage_echoesTheRefreshedBody() async throws {
        let spy = SpyDeleteMarkdownImage(refreshedBody: "notes after removal")
        let sut = makeGateway(editCard: SpyEditCard(),
                              loadCardDetail: StubLoadCardDetailWithBody(markdown: "stale"),
                              saveImageAsset: SpySaveImageAsset(assetID: UUID()),
                              deleteMarkdownImage: spy)

        let json = try await sut.deleteMarkdownImage(cardID: cardID.uuidString, assetID: UUID().uuidString)

        // The echoed body is the mutation's refreshed detail (carried for this card), not a re-read.
        XCTAssertTrue(json.contains("notes after removal"))
    }

    func testDeleteMarkdownImage_invalidAssetID_throwsBadUUID() async throws {
        let sut = makeGateway(editCard: SpyEditCard(),
                              loadCardDetail: StubLoadCardDetailWithBody(markdown: ""),
                              saveImageAsset: SpySaveImageAsset(assetID: UUID()))

        do {
            _ = try await sut.deleteMarkdownImage(cardID: cardID.uuidString, assetID: "not-a-uuid")
            XCTFail("Expected badUUID to be thrown")
        } catch let error as KanvasMCPError {
            guard case .badUUID = error else { return XCTFail("Expected .badUUID, got \(error)") }
        }
    }
}

private final class SpyDeleteMarkdownImage: AsyncUseCase, @unchecked Sendable {
    private let refreshedBody: String
    private(set) var lastRequest: DeleteMarkdownImageRequest?
    init(refreshedBody: String) { self.refreshedBody = refreshedBody }
    func execute(_ request: DeleteMarkdownImageRequest) async throws -> BoardMutationResponse {
        lastRequest = request
        return boardMutation(detail: cardDetailFixture(id: request.cardID, markdown: refreshedBody))
    }
}

// MARK: - Spies / stubs

private final class SpySaveImageAsset: AsyncUseCase, @unchecked Sendable {
    private let assetID: UUID
    private(set) var lastImageData: Data?
    init(assetID: UUID) { self.assetID = assetID }
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        lastImageData = request.imageData
        return SaveImageAssetResponse(assetID: assetID)
    }
}

private final class SpyEditCard: AsyncUseCase, @unchecked Sendable {
    private(set) var lastMarkdownContent: String?
    func execute(_ request: EditCardRequest) async throws -> BoardMutationResponse {
        lastMarkdownContent = request.markdownContent
        return boardMutation(detail: cardDetailFixture(id: request.cardID,
                                                        markdown: request.markdownContent ?? ""))
    }
}

private final class StubLoadCardDetailWithBody: LoadCardDetailUseCase, @unchecked Sendable {
    private let markdown: String
    init(markdown: String) { self.markdown = markdown }
    func execute(cardID: UUID) async throws -> CardDetailResponse? {
        cardDetailFixture(id: cardID, markdown: markdown)
    }
}

// MARK: - Fixtures

private func boardResponseFixture(id: UUID = UUID()) -> BoardResponse {
    BoardResponse(
        board: BoardSummary(id: id, title: ""),
        columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
    )
}

private func boardMutation(detail: CardDetailResponse?) -> BoardMutationResponse {
    BoardMutationResponse(board: boardResponseFixture(), cardDetail: detail)
}

private func cardDetailFixture(id: UUID, markdown: String) -> CardDetailResponse {
    CardDetailResponse(
        id: id, title: "Card", markdownContent: markdown,
        status: .todo, columnTitle: "To Do",
        schedule: nil, labels: [], assignee: nil, prURL: nil, completedAt: nil,
        stickies: [], shapes: [], images: [], texts: [], connectors: []
    )
}

// MARK: - Gateway factory

private func makeGateway(
    editCard: EditCardUseCase,
    loadCardDetail: any LoadCardDetailUseCase,
    saveImageAsset: SaveImageAssetUseCase,
    deleteMarkdownImage: DeleteMarkdownImageUseCase = MutStub<DeleteMarkdownImageRequest>()
) -> KanvasMCPGateway {
    KanvasMCPGateway(
        loadActiveBoard: BoardStub<LoadActiveBoardRequest>(),
        loadBoardByID: BoardStub<LoadBoardByIDRequest>(),
        listBoards: ListBoardsStub(),
        addCard: AddCardStub(),
        editCard: editCard,
        moveCard: MutStub<MoveCardRequest>(),
        deleteCard: BoardStub<DeleteCardRequest>(),
        addColumn: BoardStub<AddColumnRequest>(),
        renameColumn: BoardStub<RenameColumnRequest>(),
        deleteColumn: BoardStub<DeleteColumnRequest>(),
        editBoardSettings: BoardStub<EditBoardSettingsRequest>(),
        editColumnAppearance: BoardStub<EditColumnAppearanceRequest>(),
        loadCardDetail: loadCardDetail,
        addSticky: MutStub<AddStickyRequest>(),
        editSticky: MutStub<EditStickyRequest>(),
        moveSticky: MutStub<MoveStickyRequest>(),
        setStickyFrame: MutStub<SetStickyFrameRequest>(),
        deleteSticky: MutStub<DeleteStickyRequest>(),
        promoteSticky: MutStub<PromoteStickyRequest>(),
        demoteSticky: MutStub<DemoteStickyRequest>(),
        addText: MutStub<AddTextRequest>(),
        editText: MutStub<EditTextRequest>(),
        moveText: MutStub<MoveTextRequest>(),
        resizeText: MutStub<ResizeTextRequest>(),
        setTextColor: MutStub<SetTextColorRequest>(),
        setTextFontSize: MutStub<SetTextFontSizeRequest>(),
        deleteText: MutStub<DeleteTextRequest>(),
        addConnector: MutStub<AddConnectorRequest>(),
        deleteConnector: MutStub<DeleteConnectorRequest>(),
        setConnectorStyle: MutStub<SetConnectorStyleRequest>(),
        reconnectConnector: MutStub<ReconnectConnectorRequest>(),
        saveImageAsset: saveImageAsset,
        deleteMarkdownImage: deleteMarkdownImage
    )
}

private struct MutStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse { boardMutation(detail: nil) }
}

private struct BoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { boardResponseFixture() }
}

private struct ListBoardsStub: AsyncUseCase, Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        BoardListResponse(boards: [], activeBoardID: nil)
    }
}

private struct AddCardStub: AsyncUseCase, Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: boardResponseFixture())
    }
}
