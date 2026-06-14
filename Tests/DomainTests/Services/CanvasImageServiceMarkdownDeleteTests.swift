import XCTest
@testable import KanvasCore

/// `CanvasImageService.deleteMarkdownImage` (ticket 2A2784BE): the user-initiated Markdown image
/// deletion — removes the first body reference, then reclaims the asset bytes **iff** no card / Canvas
/// placement on any board still references the id (a refcount). Covers the gerund (`removingMarkdownReference`)
/// not-found paths and the verb's reclaim-vs-keep branch via the stub asset store's `deletedAssetIDs`.
final class CanvasImageServiceMarkdownDeleteTests: XCTestCase {

    private func board(cards: [Card] = [], images: [CanvasImage] = []) -> BoardState {
        BoardState(board: Board(title: "B"), columns: [], cards: cards, stickies: [], images: images)
    }

    private func sut(state: BoardState, assets: StubImageAssetRepository = StubImageAssetRepository())
        -> (CanvasImageService, StubImageAssetRepository) {
        let service = CanvasImageService(repository: StubBoardRepository(state: state),
                                         imageAssetRepository: assets,
                                         diagnostics: SpyDiagnosticsLogger())
        return (service, assets)
    }

    private func card(_ id: UUID = UUID(), body: String) -> Card {
        Card(id: id, columnID: UUID(), title: "Note", markdownContent: body, sortIndex: 0)
    }

    private func expectThrows(_ body: () async throws -> Void,
                              inspect: (Error) -> Void = { _ in },
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await body()
            XCTFail("expected an error to be thrown", file: file, line: line)
        } catch {
            inspect(error)
        }
    }

    // MARK: - removingMarkdownReference (pure transform)

    func testRemovingMarkdownReference_stripsReferenceFromBody() throws {
        let assetID = UUID()
        let cardID = UUID()
        let body = "notes\n\(MarkdownImageReference.markdown(for: assetID))\nmore"
        let (service, _) = sut(state: board(cards: [card(cardID, body: body)]))

        let result = try service.removingMarkdownReference(to: assetID, fromCard: cardID,
                                                           in: board(cards: [card(cardID, body: body)]))

        XCTAssertEqual(result.cards.first?.markdownContent, "notes\nmore")
    }

    func testRemovingMarkdownReference_unknownCard_throwsNotFound() {
        let missingCard = UUID()
        let (service, _) = sut(state: board())

        XCTAssertThrowsError(
            try service.removingMarkdownReference(to: UUID(), fromCard: missingCard, in: board())
        ) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Card", id: missingCard))
        }
    }

    func testRemovingMarkdownReference_referenceAbsent_throwsNotFoundImage() {
        let cardID = UUID()
        let absentAsset = UUID()
        let state = board(cards: [card(cardID, body: "no images here")])

        let (service, _) = sut(state: state)

        XCTAssertThrowsError(
            try service.removingMarkdownReference(to: absentAsset, fromCard: cardID, in: state)
        ) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Image", id: absentAsset))
        }
    }

    // MARK: - deleteMarkdownImage (imperative verb: refcount reclaim)

    func testDeleteMarkdownImage_lastReference_reclaimsBytes() async throws {
        let assetID = UUID()
        let cardID = UUID()
        let body = MarkdownImageReference.markdown(for: assetID)
        let (service, assets) = sut(state: board(cards: [card(cardID, body: body)]))

        _ = try await service.deleteMarkdownImage(cardID: cardID, assetID: assetID)

        // No remaining reference anywhere → bytes reclaimed immediately, not left to the orphan GC.
        XCTAssertEqual(assets.deletedAssetIDs, [assetID])
    }

    func testDeleteMarkdownImage_removesTheReferenceFromTheBody() async throws {
        let assetID = UUID()
        let cardID = UUID()
        let body = "intro\n\(MarkdownImageReference.markdown(for: assetID))\noutro"
        let (service, _) = sut(state: board(cards: [card(cardID, body: body)]))

        let newState = try await service.deleteMarkdownImage(cardID: cardID, assetID: assetID)

        XCTAssertEqual(newState.cards.first?.markdownContent, "intro\noutro")
    }

    func testDeleteMarkdownImage_duplicateReferenceOnSameCard_keepsBytes() async throws {
        let assetID = UUID()
        let cardID = UUID()
        let reference = MarkdownImageReference.markdown(for: assetID)
        let body = "\(reference)\n\(reference)"
        let (service, assets) = sut(state: board(cards: [card(cardID, body: body)]))

        _ = try await service.deleteMarkdownImage(cardID: cardID, assetID: assetID)

        // One reference still remains after the first is removed → bytes kept (refcount > 0).
        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testDeleteMarkdownImage_referencedByAnotherCard_keepsBytes() async throws {
        let assetID = UUID()
        let editedCard = UUID()
        let otherCard = UUID()
        let reference = MarkdownImageReference.markdown(for: assetID)
        let state = board(cards: [card(editedCard, body: reference), card(otherCard, body: reference)])
        let (service, assets) = sut(state: state)

        _ = try await service.deleteMarkdownImage(cardID: editedCard, assetID: assetID)

        // The other card still references the asset → bytes kept; only the edited card's cell goes.
        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testDeleteMarkdownImage_referencedByCanvasPlacement_keepsBytes() async throws {
        let assetID = UUID()
        let cardID = UUID()
        let reference = MarkdownImageReference.markdown(for: assetID)
        let placement = CanvasImage(cardID: cardID, assetID: assetID, position: .zero,
                                    size: ImageSize(width: 100, height: 100), aspectRatio: 1, sortIndex: 0)
        let state = board(cards: [card(cardID, body: reference)], images: [placement])
        let (service, assets) = sut(state: state)

        _ = try await service.deleteMarkdownImage(cardID: cardID, assetID: assetID)

        // A Canvas image shares the asset → bytes kept even though the Markdown reference is gone.
        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testDeleteMarkdownImage_unknownReference_throwsNotFound() async {
        let cardID = UUID()
        let (service, _) = sut(state: board(cards: [card(cardID, body: "no images")]))

        await expectThrows {
            _ = try await service.deleteMarkdownImage(cardID: cardID, assetID: UUID())
        } inspect: { error in
            guard case let .notFound(entityKind, _) = error as? OperationError else {
                return XCTFail("expected notFound, got \(error)")
            }
            XCTAssertEqual(entityKind, "Image")
        }
    }
}
