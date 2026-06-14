import XCTest
@testable import KanvasCore

/// Exercises the real `UseCaseContainer` to confirm that every validating use case (those whose
/// Request conforms to `ValidatableRequest`) is wrapped in a `ValidationAsyncUseCaseDecorator` in
/// DI. Feeds each with invalid input and asserts it throws — a concrete use case that bypasses
/// the decorator would succeed instead of throw, failing the test.
///
/// This covers the half the type system cannot enforce: wrapping a `ValidatableRequest` use case
/// in DI is a manual invariant. The decorator constraint prevents no-op wrapping; this test catches
/// forgotten wrapping. See `arch-usecase.md` → "Decorator pattern".
final class ValidationWiringTests: XCTestCase {

    private var useCases: UseCaseContainer!
    /// Per-test temp store. The suite builds the *real* container, so the failure mode it guards
    /// against — a `ValidatableRequest` use case left unwrapped, whose `execute()` then falls
    /// through to the real Domain Service — must not write junk into the developer's Application
    /// Support board store. Pointing the container at a throwaway directory keeps that failure
    /// hermetic (and the suite parallel-safe).
    private var storeDirectory: URL!

    override func setUp() async throws {
        try await super.setUp()
        storeDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ValidationWiringTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: storeDirectory, withIntermediateDirectories: true)
        let infra = InfrastructureContainer(directory: storeDirectory)
        let repositories = RepositoryContainer(infra: infra)
        let domain = DomainContainer(repositories: repositories)
        useCases = UseCaseContainer(domain: domain)
    }

    override func tearDown() async throws {
        useCases = nil
        if let storeDirectory {
            try? FileManager.default.removeItem(at: storeDirectory)
        }
        storeDirectory = nil
        try await super.tearDown()
    }

    // MARK: - addCardUseCase

    func testAddCard_emptyTitle_throwsBeforeWrite() async throws {
        let request = AddCardRequest(title: "   ", columnID: UUID())
        do {
            _ = try await useCases.addCardUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - addColumnUseCase

    func testAddColumn_emptyTitle_throwsBeforeWrite() async throws {
        let request = AddColumnRequest(title: "")
        do {
            _ = try await useCases.addColumnUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - addConnectorUseCase

    func testAddConnector_invalidEdge_throwsBeforeWrite() async throws {
        let request = AddConnectorRequest(
            cardID: UUID(), sourceStickyID: UUID(), sourceEdge: "invalid", targetEdge: "top",
            existingTargetStickyID: nil,
            newStickyX: 0, newStickyY: 0, newStickyWidth: 100, newStickyHeight: 100
        )
        do {
            _ = try await useCases.addConnectorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorEdge)
        }
    }

    func testAddConnector_invalidStrokeColor_throwsBeforeWrite() async throws {
        let request = AddConnectorRequest(
            cardID: UUID(), sourceStickyID: UUID(), sourceEdge: "right", targetEdge: "left",
            existingTargetStickyID: UUID(),
            newStickyX: 0, newStickyY: 0, newStickyWidth: 100, newStickyHeight: 100,
            strokeColorHex: "nothex"
        )
        do {
            _ = try await useCases.addConnectorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch is ValidationError {
            // expected — the hex invariant runs through the wired validation decorator
        }
    }

    // MARK: - addImageUseCase

    func testAddImage_emptyData_throwsBeforeWrite() async throws {
        let request = AddImageRequest(
            cardID: UUID(), imageData: Data(),
            positionX: 0, positionY: 0, naturalWidth: 100, naturalHeight: 100
        )
        do {
            _ = try await useCases.addImageUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyImageData)
        }
    }

    // MARK: - saveImageAssetUseCase

    func testSaveImageAsset_emptyData_throwsBeforeWrite() async throws {
        let request = SaveImageAssetRequest(imageData: Data())
        do {
            _ = try await useCases.saveImageAssetUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyImageData)
        }
    }

    // MARK: - addStickyUseCase

    func testAddSticky_contentTooLong_throwsBeforeWrite() async throws {
        let request = AddStickyRequest(
            cardID: UUID(),
            content: String(repeating: "x", count: ContentSizeValidation.maxStickyContentLength + 1),
            positionX: 0, positionY: 0, width: 100, height: 100, fillColorHex: nil
        )
        do {
            _ = try await useCases.addStickyUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .contentTooLong(max: ContentSizeValidation.maxStickyContentLength))
        }
    }

    // MARK: - editStickyUseCase

    func testEditSticky_contentTooLong_throwsBeforeWrite() async throws {
        let request = EditStickyRequest(
            stickyID: UUID(),
            content: String(repeating: "x", count: ContentSizeValidation.maxStickyContentLength + 1)
        )
        do {
            _ = try await useCases.editStickyUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .contentTooLong(max: ContentSizeValidation.maxStickyContentLength))
        }
    }

    // MARK: - addLabelUseCase

    func testAddLabel_emptyName_throwsBeforeWrite() async throws {
        let request = AddLabelRequest(name: "", colorHex: "FF0000")
        do {
            _ = try await useCases.addLabelUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyLabelName)
        }
    }

    // MARK: - addShapeUseCase

    func testAddShape_emptyKind_throwsBeforeWrite() async throws {
        let request = AddShapeRequest(
            cardID: UUID(), kind: "", topology: "box",
            positionX: 0, positionY: 0, width: 100, height: 100
        )
        do {
            _ = try await useCases.addShapeUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidShapeKind)
        }
    }

    // MARK: - addBoardUseCase

    func testAddBoard_emptyTitle_throwsBeforeWrite() async throws {
        let request = AddBoardRequest(title: "  ")
        do {
            _ = try await useCases.addBoardUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - editCardUseCase

    func testEditCard_emptyTitle_throwsBeforeWrite() async throws {
        let request = EditCardRequest(cardID: UUID(), title: "  ")
        do {
            _ = try await useCases.editCardUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - editLabelUseCase

    func testEditLabel_emptyName_throwsBeforeWrite() async throws {
        let request = EditLabelRequest(labelID: UUID(), name: "", colorHex: "FF0000")
        do {
            _ = try await useCases.editLabelUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyLabelName)
        }
    }

    // MARK: - renameBoardUseCase

    func testRenameBoard_emptyTitle_throwsBeforeWrite() async throws {
        let request = RenameBoardRequest(boardID: UUID(), title: "  ")
        do {
            _ = try await useCases.renameBoardUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - renameColumnUseCase

    func testRenameColumn_emptyTitle_throwsBeforeWrite() async throws {
        let request = RenameColumnRequest(columnID: UUID(), title: "  ")
        do {
            _ = try await useCases.renameColumnUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .emptyTitle)
        }
    }

    // MARK: - setConnectorCapUseCase

    func testSetConnectorCap_invalidCap_throwsBeforeWrite() async throws {
        let request = SetConnectorCapRequest(connectorID: UUID(), cap: "invalid")
        do {
            _ = try await useCases.setConnectorCapUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorCap)
        }
    }

    // MARK: - setConnectorRoutingUseCase

    func testSetConnectorRouting_invalidRouting_throwsBeforeWrite() async throws {
        let request = SetConnectorRoutingRequest(connectorID: UUID(), routing: "invalid")
        do {
            _ = try await useCases.setConnectorRoutingUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorRouting)
        }
    }

    // MARK: - setConnectorStrokeColorUseCase

    func testSetConnectorStrokeColor_invalidHex_throwsBeforeWrite() async throws {
        let request = SetConnectorStrokeColorRequest(connectorID: UUID(), colorHex: "ZZZ")
        do {
            _ = try await useCases.setConnectorStrokeColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setConnectorStrokeWidthUseCase

    func testSetConnectorStrokeWidth_outOfRange_throwsBeforeWrite() async throws {
        let request = SetConnectorStrokeWidthRequest(connectorID: UUID(), width: 0)
        do {
            _ = try await useCases.setConnectorStrokeWidthUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    // MARK: - setConnectorWaypointUseCase

    func testSetConnectorWaypoint_halfSpecifiedOffset_throwsBeforeWrite() async throws {
        let request = SetConnectorWaypointRequest(connectorID: UUID(), offsetX: 5, offsetY: nil)
        do {
            _ = try await useCases.setConnectorWaypointUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorWaypoint)
        }
    }

    // MARK: - setConnectorStyleUseCase

    func testSetConnectorStyle_invalidCap_throwsBeforeWrite() async throws {
        let request = SetConnectorStyleRequest(
            connectorID: UUID(), cap: "invalid", routing: nil, strokeColorHex: nil, strokeWidth: nil
        )
        do {
            _ = try await useCases.setConnectorStyleUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorCap)
        }
    }

    func testSetConnectorStyle_outOfRangeStrokeWidth_throwsBeforeWrite() async throws {
        let request = SetConnectorStyleRequest(
            connectorID: UUID(), cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: .nan
        )
        do {
            _ = try await useCases.setConnectorStyleUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    // MARK: - reconnectConnectorUseCase

    func testReconnectConnector_invalidEdge_throwsBeforeWrite() async throws {
        let request = ReconnectConnectorRequest(
            connectorID: UUID(), sourceStickyID: UUID(), sourceEdge: "sideways"
        )
        do {
            _ = try await useCases.reconnectConnectorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidConnectorEdge)
        }
    }

    // MARK: - setShapeFillColorUseCase

    func testSetShapeFillColor_invalidHex_throwsBeforeWrite() async throws {
        let request = SetShapeFillColorRequest(shapeID: UUID(), colorHex: "ZZZZZ")
        do {
            _ = try await useCases.setShapeFillColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setShapeStrokeColorUseCase

    func testSetShapeStrokeColor_invalidHex_throwsBeforeWrite() async throws {
        let request = SetShapeStrokeColorRequest(shapeID: UUID(), colorHex: "ZZZ")
        do {
            _ = try await useCases.setShapeStrokeColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setTextColorUseCase

    func testSetTextColor_invalidHex_throwsBeforeWrite() async throws {
        let request = SetTextColorRequest(textID: UUID(), colorHex: "ZZZ")
        do {
            _ = try await useCases.setTextColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setTextFontSizeUseCase

    func testSetTextFontSize_outOfRange_throwsBeforeWrite() async throws {
        let request = SetTextFontSizeRequest(textID: UUID(), fontSize: .nan)
        do {
            _ = try await useCases.setTextFontSizeUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .fontSizeOutOfRange(
                min: CanvasTextStyle.minFontSize, max: CanvasTextStyle.maxFontSize
            ))
        }
    }

    // MARK: - setShapeStrokeWidthUseCase

    func testSetShapeStrokeWidth_outOfRange_throwsBeforeWrite() async throws {
        let request = SetShapeStrokeWidthRequest(shapeID: UUID(), width: .nan)
        do {
            _ = try await useCases.setShapeStrokeWidthUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .strokeWidthOutOfRange(
                min: CanvasShapeStyle.minStrokeWidth, max: CanvasShapeStyle.maxStrokeWidth
            ))
        }
    }

    // MARK: - setStickyTextColorUseCase

    func testSetStickyTextColor_invalidHex_throwsBeforeWrite() async throws {
        // "GGGGGG" is 6 chars but non-hex, so only the hex-digit check fails (not the length
        // check) — isolating which invariant the decorator enforces.
        let request = SetStickyTextColorRequest(stickyID: UUID(), colorHex: "GGGGGG")
        do {
            _ = try await useCases.setStickyTextColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setStickyFillColorUseCase

    func testSetStickyFillColor_invalidHex_throwsBeforeWrite() async throws {
        let request = SetStickyFillColorRequest(stickyID: UUID(), fillColorHex: "GGGGGG")
        do {
            _ = try await useCases.setStickyFillColorUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }

    // MARK: - setStickyFontSizeUseCase

    func testSetStickyFontSize_outOfRange_throwsBeforeWrite() async throws {
        let request = SetStickyFontSizeRequest(stickyID: UUID(), fontSize: 0)
        do {
            _ = try await useCases.setStickyFontSizeUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    // MARK: - addTextUseCase

    func testAddText_contentTooLong_throwsBeforeWrite() async throws {
        let request = AddTextRequest(
            cardID: UUID(),
            content: String(repeating: "x", count: ContentSizeValidation.maxStickyContentLength + 1),
            positionX: 0, positionY: 0, width: 100, height: 100
        )
        do {
            _ = try await useCases.addTextUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .contentTooLong(max: ContentSizeValidation.maxStickyContentLength))
        }
    }

    // MARK: - editTextUseCase

    func testEditText_contentTooLong_throwsBeforeWrite() async throws {
        let request = EditTextRequest(
            textID: UUID(),
            content: String(repeating: "x", count: ContentSizeValidation.maxStickyContentLength + 1)
        )
        do {
            _ = try await useCases.editTextUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .contentTooLong(max: ContentSizeValidation.maxStickyContentLength))
        }
    }

    // MARK: - coordinate-finiteness wiring (ticket 4FD6D166)

    func testMoveSticky_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = MoveStickyRequest(stickyID: UUID(), positionX: .nan, positionY: 0)
        do {
            _ = try await useCases.moveStickyUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testSetStickyFrame_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = SetStickyFrameRequest(
            stickyID: UUID(), width: 100, height: 100, positionX: 0, positionY: .infinity
        )
        do {
            _ = try await useCases.setStickyFrameUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testMoveShape_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = MoveShapeRequest(shapeID: UUID(), positionX: .nan, positionY: 0)
        do {
            _ = try await useCases.moveShapeUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testResizeShape_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = ResizeShapeRequest(
            shapeID: UUID(), width: 100, height: 100, positionX: .nan, positionY: 0, lineRising: nil
        )
        do {
            _ = try await useCases.resizeShapeUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testMoveText_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = MoveTextRequest(textID: UUID(), positionX: 0, positionY: .nan)
        do {
            _ = try await useCases.moveTextUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testResizeText_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = ResizeTextRequest(
            textID: UUID(), width: 100, height: 100, positionX: .infinity, positionY: 0
        )
        do {
            _ = try await useCases.resizeTextUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testMoveImage_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = MoveImageRequest(imageID: UUID(), positionX: .nan, positionY: 0)
        do {
            _ = try await useCases.moveImageUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testResizeImage_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = ResizeImageRequest(
            imageID: UUID(), width: 100, height: 100, positionX: 0, positionY: .nan
        )
        do {
            _ = try await useCases.resizeImageUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testMoveCanvasGroup_nonFiniteCoordinate_throwsBeforeWrite() async throws {
        let request = MoveCanvasGroupRequest(
            movements: [.init(id: UUID(), positionX: .nan, positionY: 0)],
            cardID: UUID()
        )
        do {
            _ = try await useCases.moveCanvasGroupUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    func testSetConnectorWaypoint_nonFiniteOffset_throwsBeforeWrite() async throws {
        let request = SetConnectorWaypointRequest(connectorID: UUID(), offsetX: .nan, offsetY: 4)
        do {
            _ = try await useCases.setConnectorWaypointUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .nonFiniteCoordinate)
        }
    }

    // MARK: - editColumnAppearanceUseCase

    func testEditColumnAppearance_invalidHex_throwsBeforeWrite() async throws {
        // A *set* colour (.some(.some)) that is not bare 6-digit hex must be rejected by the wired
        // decorator before any mutation — the cross-surface format fix (ticket C5994D2A).
        let request = EditColumnAppearanceRequest(
            columnID: UUID(),
            headerColorHex: .some(.some("#FF0000")),  // '#'-prefixed is no longer valid
            headerTextColorHex: nil, bodyColorHex: nil, headerBorderColorHex: nil,
            bodyBorderColorHex: nil, indicatorColorHex: nil, isCompletionColumn: nil
        )
        do {
            _ = try await useCases.editColumnAppearanceUseCase.execute(request)
            XCTFail("Expected a ValidationError to be thrown")
        } catch let error as ValidationError {
            XCTAssertEqual(error, .invalidColorHex)
        }
    }
}
