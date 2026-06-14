import XCTest
@testable import KanvasCore

/// Tests for `board_column_appearance_edit`'s gateway path: hex validation before any write, the
/// wire-sentinel → keep/clear/set mapping (`keepClearSet`), and delegation to the atomic
/// `EditColumnAppearanceUseCase` (ticket 620B3601 replaced the former two-flock read-modify-write
/// over the batch `EditBoardSettings` with one mutation in the Domain Service — the keep/clear/set
/// overlay and single-completion invariant are now covered by the Domain tests).
final class KanvasMCPColumnAppearanceTests: XCTestCase {

    // MARK: - keepClearSet (wire sentinel → Request double-optional)

    func testKeepClearSet_omittedArgument_isKeep() {
        // nil (omitted) → nil (outer) = keep.
        XCTAssertNil(KanvasMCPGateway.keepClearSet(nil))
    }

    func testKeepClearSet_emptyString_isClear() {
        // "" (clear sentinel) → .some(nil) = clear to system default.
        let result = KanvasMCPGateway.keepClearSet("")
        XCTAssertNotNil(result)            // outer .some
        XCTAssertNil(result ?? "x")        // inner nil
    }

    func testKeepClearSet_nonEmptyString_isSet() {
        XCTAssertEqual(KanvasMCPGateway.keepClearSet("445566"), "445566")
    }

    // MARK: - delegation to the use case

    func testEditColumnAppearance_mapsTargetColumnID() async throws {
        let columnID = UUID()
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: columnID.uuidString,
            appearance: edit(headerColorHex: "FF0000", isCompletionColumn: true)
        )

        XCTAssertEqual(capture.captured?.columnID, columnID)
    }

    func testEditColumnAppearance_mapsSetColourToSetIntent() async throws {
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: UUID().uuidString, appearance: edit(headerColorHex: "FF0000")
        )

        XCTAssertEqual(capture.captured?.headerColorHex, "FF0000")
    }

    func testEditColumnAppearance_mapsOmittedColourToKeep() async throws {
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: UUID().uuidString, appearance: edit(headerColorHex: "FF0000")  // body omitted
        )

        // bodyColorHex omitted → nil (outer) = keep. `captured` is non-nil, so the inner double-
        // optional being nil means the outer was nil (keep), not .some(nil) (clear).
        let captured = try XCTUnwrap(capture.captured)
        XCTAssertNil(captured.bodyColorHex)
    }

    func testEditColumnAppearance_mapsEmptyColourToClear() async throws {
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: UUID().uuidString, appearance: edit(headerColorHex: "")  // clear sentinel
        )

        // .some(nil): the key was provided (outer .some) but cleared (inner nil).
        let mapped = try XCTUnwrap(capture.captured?.headerColorHex)  // outer .some
        XCTAssertNil(mapped)                                          // inner nil
    }

    func testEditColumnAppearance_mapsCompletionFlag() async throws {
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: UUID().uuidString, appearance: edit(isCompletionColumn: true)
        )

        XCTAssertEqual(capture.captured?.isCompletionColumn, true)
    }

    // MARK: - hex colour validation (still owned by the gateway, before any write)

    func testIsValidHexColor_accepts6DigitBareHex() {
        XCTAssertTrue(KanvasMCPGateway.isValidHexColor("3478F6"))
    }

    func testIsValidHexColor_acceptsLowercase() {
        XCTAssertTrue(KanvasMCPGateway.isValidHexColor("abcdef"))
    }

    func testIsValidHexColor_rejectsLeadingHash() {
        // The whole system (store seed, Color.toHex, LabelValidation) uses bare 6-digit; a
        // '#'-prefixed string is now rejected so the MCP path converges on one format.
        XCTAssertFalse(KanvasMCPGateway.isValidHexColor("#3478F6"))
    }

    func testIsValidHexColor_rejects3DigitShorthand() {
        XCTAssertFalse(KanvasMCPGateway.isValidHexColor("abc"))
    }

    func testIsValidHexColor_rejects8DigitWithAlpha() {
        XCTAssertFalse(KanvasMCPGateway.isValidHexColor("3478F6FF"))
    }

    func testIsValidHexColor_rejectsNonHexDigits() {
        XCTAssertFalse(KanvasMCPGateway.isValidHexColor("not-a-hex"))
    }

    func testIsValidHexColor_rejectsWrongLength() {
        XCTAssertFalse(KanvasMCPGateway.isValidHexColor("FFFF"))
    }

    func testEditColumnAppearance_malformedHex_throwsBadHexColorBeforeWrite() async throws {
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        do {
            _ = try await sut.editColumnAppearance(
                columnID: UUID().uuidString, appearance: edit(headerColorHex: "not-a-hex")
            )
            XCTFail("Expected badHexColor")
        } catch let error as KanvasMCPError {
            if case .badHexColor(let field, _) = error {
                XCTAssertEqual(field, "headerColorHex")
            } else {
                XCTFail("Expected badHexColor, got \(error)")
            }
        }
        XCTAssertNil(capture.captured)  // never reached the use case
    }

    func testEditColumnAppearance_emptyStringHex_passesValidation() async throws {
        // "" is the clear sentinel, not a malformed colour — it must NOT be rejected.
        let capture = CaptureEditColumnAppearance()
        let sut = makeColumnGateway(editColumnAppearance: capture)

        _ = try await sut.editColumnAppearance(
            columnID: UUID().uuidString, appearance: edit(headerColorHex: "")
        )

        XCTAssertNotNil(capture.captured)  // reached the use case
    }
}

// MARK: - Fixtures + helpers

private func edit(
    headerColorHex: String? = nil,
    headerTextColorHex: String? = nil,
    bodyColorHex: String? = nil,
    headerBorderColorHex: String? = nil,
    bodyBorderColorHex: String? = nil,
    indicatorColorHex: String? = nil,
    isCompletionColumn: Bool? = nil
) -> ColumnAppearanceEdit {
    ColumnAppearanceEdit(
        headerColorHex: headerColorHex,
        headerTextColorHex: headerTextColorHex,
        bodyColorHex: bodyColorHex,
        headerBorderColorHex: headerBorderColorHex,
        bodyBorderColorHex: bodyBorderColorHex,
        indicatorColorHex: indicatorColorHex,
        isCompletionColumn: isCompletionColumn
    )
}

/// Captures the `EditColumnAppearanceRequest` the gateway builds — the assertion target for the
/// wire-sentinel → keep/clear/set mapping and the column-id pass-through.
private final class CaptureEditColumnAppearance: AsyncUseCase, @unchecked Sendable {
    private(set) var captured: EditColumnAppearanceRequest?
    func execute(_ request: EditColumnAppearanceRequest) async throws -> BoardResponse {
        captured = request
        return BoardResponse(
            board: BoardSummary(id: UUID(), title: "Test"),
            columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
        )
    }
}

private func makeColumnGateway(
    editColumnAppearance: EditColumnAppearanceUseCase
) -> KanvasMCPGateway {
    KanvasMCPGateway(
        loadActiveBoard: ColAppBoardStub<LoadActiveBoardRequest>(),
        loadBoardByID: ColAppBoardStub<LoadBoardByIDRequest>(),
        listBoards: ColAppListBoardsStub(),
        addCard: ColAppAddCardStub(),
        editCard: ColAppMutStub<EditCardRequest>(),
        moveCard: ColAppMutStub<MoveCardRequest>(),
        deleteCard: ColAppBoardStub<DeleteCardRequest>(),
        addColumn: ColAppBoardStub<AddColumnRequest>(),
        renameColumn: ColAppBoardStub<RenameColumnRequest>(),
        deleteColumn: ColAppBoardStub<DeleteColumnRequest>(),
        editBoardSettings: ColAppBoardStub<EditBoardSettingsRequest>(),
        editColumnAppearance: editColumnAppearance,
        loadCardDetail: ColAppLoadCardDetailStub(),
        addSticky: ColAppMutStub<AddStickyRequest>(),
        editSticky: ColAppMutStub<EditStickyRequest>(),
        moveSticky: ColAppMutStub<MoveStickyRequest>(),
        setStickyFrame: ColAppMutStub<SetStickyFrameRequest>(),
        deleteSticky: ColAppMutStub<DeleteStickyRequest>(),
        promoteSticky: ColAppMutStub<PromoteStickyRequest>(),
        demoteSticky: ColAppMutStub<DemoteStickyRequest>(),
        addText: ColAppMutStub<AddTextRequest>(),
        editText: ColAppMutStub<EditTextRequest>(),
        moveText: ColAppMutStub<MoveTextRequest>(),
        resizeText: ColAppMutStub<ResizeTextRequest>(),
        setTextColor: ColAppMutStub<SetTextColorRequest>(),
        setTextFontSize: ColAppMutStub<SetTextFontSizeRequest>(),
        deleteText: ColAppMutStub<DeleteTextRequest>(),
        addConnector: ColAppMutStub<AddConnectorRequest>(),
        deleteConnector: ColAppMutStub<DeleteConnectorRequest>(),
        setConnectorStyle: ColAppMutStub<SetConnectorStyleRequest>(),
        reconnectConnector: ColAppMutStub<ReconnectConnectorRequest>(),
        saveImageAsset: ColAppSaveImageAssetStub(),
        deleteMarkdownImage: ColAppMutStub<DeleteMarkdownImageRequest>()
    )
}

private func colAppBoardResponse() -> BoardResponse {
    BoardResponse(
        board: BoardSummary(id: UUID(), title: ""),
        columns: [], labels: [], settings: SettingsTestFixtures.defaultSettings
    )
}

private func colAppBoardMutation() -> BoardMutationResponse {
    BoardMutationResponse(board: colAppBoardResponse(), cardDetail: nil)
}

private struct ColAppMutStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardMutationResponse { colAppBoardMutation() }
}

private struct ColAppBoardStub<R: UseCaseRequest>: AsyncUseCase, Sendable {
    func execute(_ request: R) async throws -> BoardResponse { colAppBoardResponse() }
}

private struct ColAppListBoardsStub: AsyncUseCase, Sendable {
    func execute(_ request: ListBoardsRequest) async throws -> BoardListResponse {
        BoardListResponse(boards: [], activeBoardID: nil)
    }
}

private struct ColAppAddCardStub: AsyncUseCase, Sendable {
    func execute(_ request: AddCardRequest) async throws -> AddCardResponse {
        AddCardResponse(newCardID: UUID(), board: colAppBoardResponse())
    }
}

private struct ColAppSaveImageAssetStub: AsyncUseCase, Sendable {
    func execute(_ request: SaveImageAssetRequest) async throws -> SaveImageAssetResponse {
        SaveImageAssetResponse(assetID: UUID())
    }
}

private struct ColAppLoadCardDetailStub: LoadCardDetailUseCase, Sendable {
    func execute(cardID: UUID) async throws -> CardDetailResponse? { nil }
}
