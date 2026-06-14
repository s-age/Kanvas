import XCTest
@testable import KanvasCore

/// `CanvasImageService` pure transforms: create/move/resize/z-order/delete + the `fittedSize`
/// helper. The z-order tests pin the design rule — images share the canvas `sortIndex` space with
/// stickies *and* shapes; the resize tests pin aspect-ratio preservation (height follows width).
final class CanvasImageServiceTests: XCTestCase {

    private var service: CanvasImageService!

    override func setUp() {
        super.setUp()
        service = CanvasImageService(repository: StubBoardRepository(),
                                     imageAssetRepository: StubImageAssetRepository(),
                                     diagnostics: SpyDiagnosticsLogger())
    }

    // MARK: - sweepOrphanedAssets

    /// Builds a service over a single board holding `images`, with the asset store reporting
    /// `candidates` as old enough to sweep. Returns the asset stub + diagnostics spy so a test can
    /// assert deletions and the emitted observability.
    private func sweepFixture(images: [CanvasImage], candidates: Set<UUID>,
                              loadFails: Bool = false)
        -> (CanvasImageService, StubImageAssetRepository, SpyDiagnosticsLogger) {
        let board = StubBoardRepository(state: state(images: images))
        if loadFails { board.loadBoardError = OperationError.loadFailed }
        let assets = StubImageAssetRepository()
        assets.sweepableIDs = candidates
        let diagnostics = SpyDiagnosticsLogger()
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets, diagnostics: diagnostics)
        return (sut, assets, diagnostics)
    }

    /// Async equivalent of `XCTAssertThrowsError`, which cannot take an `async` autoclosure
    /// (see `test-unit.md` → "Async error testing").
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

    func testSweep_deletesUnreferencedCandidate() async throws {
        let referenced = image()
        let orphan = UUID()
        let (sut, assets, _) = sweepFixture(images: [referenced],
                                            candidates: [referenced.assetID, orphan])

        try await sut.sweepOrphanedAssets()

        XCTAssertEqual(assets.deletedAssetIDs, [orphan])
    }

    func testSweep_keepsAssetReferencedByABoard() async throws {
        let referenced = image()
        let (sut, assets, _) = sweepFixture(images: [referenced], candidates: [referenced.assetID])

        try await sut.sweepOrphanedAssets()

        XCTAssertFalse(assets.deletedAssetIDs.contains(referenced.assetID))
    }

    func testSweep_noCandidates_skipsReachabilityAndDeletesNothing() async throws {
        let (sut, assets, _) = sweepFixture(images: [], candidates: [])

        try await sut.sweepOrphanedAssets()

        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testSweep_abortsWithoutDeletingWhenABoardFailsToLoad() async {
        let orphan = UUID()
        let (sut, assets, _) = sweepFixture(images: [], candidates: [orphan], loadFails: true)

        await expectThrows { try await sut.sweepOrphanedAssets() }
        // Reachability is unknown when a board cannot load, so nothing is reclaimed.
        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testSweep_abortsWithoutDeletingWhenABoardSnapshotIsUnreadable() async {
        // Per-record fail-open read: the list does not throw, but it reports an undecodable board in
        // `unreadableBoardIDs`. Reachability is then incomplete, so the GC must still abort — a
        // referenced asset on the unreadable board would otherwise look orphaned and be reclaimed.
        let orphan = UUID()
        let board = StubBoardRepository(state: state(images: []))
        board.unreadableBoardIDs = [UUID()]
        let assets = StubImageAssetRepository()
        assets.sweepableIDs = [orphan]
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())

        await expectThrows { try await sut.sweepOrphanedAssets() }
        XCTAssertTrue(assets.deletedAssetIDs.isEmpty)
    }

    func testSweep_unreadableBoardAbort_errorNamesTheUndecodableBoard() async {
        // The abort is `inconsistentState` (not `fileCorrupted`: the read succeeded, reachability is
        // merely incomplete) and carries the undecodable board id so the single abort line is
        // self-describing — correlatable to the boards without scraping the repo's per-id logs.
        let unreadable = UUID()
        let board = StubBoardRepository(state: state(images: []))
        board.unreadableBoardIDs = [unreadable]
        let assets = StubImageAssetRepository()
        assets.sweepableIDs = [UUID()]
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())

        await expectThrows { try await sut.sweepOrphanedAssets() } inspect: { error in
            guard case let .inconsistentState(reason) = error as? OperationError else {
                return XCTFail("expected inconsistentState, got \(error)")
            }
            XCTAssertTrue(reason.contains(unreadable.uuidString))
        }
    }

    // MARK: - sweepOrphanedAssets: Markdown reachability (ticket BF5746C8)

    func testSweep_keepsAssetReferencedFromCardMarkdown() async throws {
        // The asset has NO CanvasImage — only a `kanvas-asset://<id>` reference in a card's body. The
        // GC must treat that reference as reachable, else a Markdown-dropped image is reclaimed.
        let markdownAssetID = UUID()
        let card = Card(columnID: UUID(), title: "Note",
                        markdownContent: "before ![](kanvas-asset://\(markdownAssetID.uuidString)) after",
                        sortIndex: 0)
        let board = StubBoardRepository(
            state: BoardState(board: Board(title: "B"), columns: [], cards: [card], stickies: []))
        let assets = StubImageAssetRepository()
        assets.sweepableIDs = [markdownAssetID]
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())

        try await sut.sweepOrphanedAssets()

        XCTAssertFalse(assets.deletedAssetIDs.contains(markdownAssetID))
    }

    func testSweep_reclaimsAssetOnceItsMarkdownReferenceIsRemoved() async throws {
        // Same asset, but the body no longer references it (reference deleted) → now an orphan.
        let markdownAssetID = UUID()
        let card = Card(columnID: UUID(), title: "Note", markdownContent: "reference removed",
                        sortIndex: 0)
        let board = StubBoardRepository(
            state: BoardState(board: Board(title: "B"), columns: [], cards: [card], stickies: []))
        let assets = StubImageAssetRepository()
        assets.sweepableIDs = [markdownAssetID]
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())

        try await sut.sweepOrphanedAssets()

        XCTAssertEqual(assets.deletedAssetIDs, [markdownAssetID])
    }

    // MARK: - saveAsset (no board mutation)

    func testSaveAsset_persistsBytesAndReturnsID() async throws {
        let assets = StubImageAssetRepository()
        let board = StubBoardRepository(state: state())
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())
        let bytes = Data([0x1, 0x2, 0x3])

        let assetID = try await sut.saveAsset(imageData: bytes)

        XCTAssertEqual(try assets.load(assetID: assetID), bytes)
    }

    func testSaveAsset_doesNotMutateTheBoard() async throws {
        let assets = StubImageAssetRepository()
        let board = StubBoardRepository(state: state())
        let sut = CanvasImageService(repository: board, imageAssetRepository: assets,
                                     diagnostics: SpyDiagnosticsLogger())

        _ = try await sut.saveAsset(imageData: Data([0x9]))

        // No CanvasImage placed — the board carries no image after a bare asset save.
        let (states, _) = try board.loadAllBoardStates()
        XCTAssertTrue(states.allSatisfy { $0.images.isEmpty })
    }

    func testSweep_passesNowMinusGracePeriodAsCutoff() async throws {
        let fixedNow = Date(timeIntervalSince1970: 1_000_000)
        let assets = StubImageAssetRepository()
        let sut = CanvasImageService(
            repository: StubBoardRepository(state: state()),
            imageAssetRepository: assets,
            diagnostics: SpyDiagnosticsLogger(),
            gcPolicy: AssetGCPolicy(gracePeriod: 1000),
            now: { fixedNow }
        )

        try await sut.sweepOrphanedAssets()

        XCTAssertEqual(assets.receivedCutoff, fixedNow.addingTimeInterval(-1000))
    }

    // MARK: - sweepOrphanedAssets diagnostics (observability)

    func testSweep_logsReclaimedCountAtInfoLevel() async throws {
        let referenced = image()
        let orphan = UUID()
        let (sut, _, diagnostics) = sweepFixture(images: [referenced],
                                                 candidates: [referenced.assetID, orphan])

        try await sut.sweepOrphanedAssets()

        // One orphan of one (2 aged candidates, 1 reachable) reclaimed; success summary is info-level
        // and surfaces all three numbers so a hidden reachable candidate is not lost.
        XCTAssertEqual(diagnostics.messages(at: .info),
                       ["orphan-asset GC: reclaimed 1 of 1 orphan(s) (2 candidate(s) examined)"])
    }

    func testSweep_logsReachabilityAbortAtErrorLevel() async {
        let orphan = UUID()
        let (sut, _, diagnostics) = sweepFixture(images: [], candidates: [orphan], loadFails: true)

        await expectThrows { try await sut.sweepOrphanedAssets() }

        // The abort is the headline failure the ticket targets: it must surface, not stay silent.
        XCTAssertEqual(diagnostics.messages(at: .error).count, 1)
        XCTAssertTrue(diagnostics.messages(at: .error).first?.contains("aborted") ?? false)
    }

    func testSweep_abortKeepsTheUnderlyingErrorOutOfThePublicMessage() async {
        let orphan = UUID()
        let (sut, _, diagnostics) = sweepFixture(images: [], candidates: [orphan], loadFails: true)

        await expectThrows { try await sut.sweepOrphanedAssets() }

        // The raw error (which may embed a filesystem path) is carried as redacted privateDetail,
        // not interpolated into the `.public` message.
        XCTAssertFalse(diagnostics.messages(at: .error).first?.contains("loadFailed") ?? true)
        XCTAssertTrue(diagnostics.privateDetails(at: .error).contains { $0.contains("loadFailed") })
    }

    func testSweep_logsCandidateListFailureAtErrorLevel() async {
        let (sut, assets, diagnostics) = sweepFixture(images: [], candidates: [])
        assets.candidateListError = OperationError.loadFailed

        await expectThrows { try await sut.sweepOrphanedAssets() }

        // The candidate listing is the GC's last otherwise-silent throw path (the Presentation caller
        // swallows it); it must leave an error breadcrumb, with the raw error redacted to privateDetail.
        XCTAssertTrue(diagnostics.messages(at: .error).contains { $0.contains("could not list") })
        XCTAssertFalse(diagnostics.messages(at: .error).first?.contains("loadFailed") ?? true)
        XCTAssertTrue(diagnostics.privateDetails(at: .error).contains { $0.contains("loadFailed") })
    }

    func testSweep_logsPerFileDeleteFailureAtErrorLevel() async throws {
        let orphan = UUID()
        let (sut, assets, diagnostics) = sweepFixture(images: [], candidates: [orphan])
        assets.failingDeletes = [orphan]

        try await sut.sweepOrphanedAssets()

        // A single undeletable asset is reported per-file (by UUID), not swallowed by the old `try?`.
        XCTAssertTrue(diagnostics.messages(at: .error).contains { $0.contains(orphan.uuidString) })
    }

    func testSweep_summaryIsErrorLevelWhenADeleteFailed() async throws {
        let orphan = UUID()
        let (sut, assets, diagnostics) = sweepFixture(images: [], candidates: [orphan])
        assets.failingDeletes = [orphan]

        try await sut.sweepOrphanedAssets()

        // With a failure in the batch the summary itself escalates to error level.
        XCTAssertTrue(diagnostics.messages(at: .error).contains {
            $0.contains("reclaimed 0 of 1 orphan(s)") && $0.contains("1 failed")
        })
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(stickies: [Sticky] = [], shapes: [CanvasShape] = [],
                       images: [CanvasImage] = []) -> BoardState {
        BoardState(board: Board(title: "B"), columns: [], cards: [],
                   stickies: stickies, shapes: shapes, images: images)
    }

    private func asset(_ ratio: Double = 1.5) -> ImageAssetRef {
        ImageAssetRef(assetID: UUID(), aspectRatio: ratio)
    }

    private func placement(_ width: Double = 120, _ height: Double = 80) -> ImagePlacement {
        ImagePlacement(position: CanvasPosition(x: 10, y: 20), size: ImageSize(width: width, height: height))
    }

    private func image(cardID: UUID = UUID(), ratio: Double = 2, sortIndex: Int = 0) -> CanvasImage {
        CanvasImage(cardID: cardID, assetID: UUID(), position: .zero,
                    size: ImageSize(width: 200, height: 100), aspectRatio: ratio, sortIndex: sortIndex)
    }

    // MARK: - adding

    func testAdding_appendsImageReferencingTheAsset() {
        let ref = asset()

        let result = service.adding(asset: ref, placement: placement(),
                                    toCardCanvas: UUID(), in: state())

        XCTAssertEqual(result.images.first?.assetID, ref.assetID)
    }

    func testAdding_emptyCanvas_numbersFromZero() {
        let result = service.adding(asset: asset(), placement: placement(),
                                    toCardCanvas: UUID(), in: state())

        XCTAssertEqual(result.images.first?.sortIndex, 0)
    }

    func testAdding_numbersAboveExistingShapeOnSameCard() {
        let cardID = UUID()
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: 7)

        let result = service.adding(asset: asset(), placement: placement(),
                                    toCardCanvas: cardID, in: state(shapes: [shape]))

        // Shared z-order: the new image sits above the shape (7 → 8), not at 0.
        XCTAssertEqual(result.images.first?.sortIndex, 8)
    }

    // MARK: - moving

    func testMoving_updatesPosition() throws {
        let img = image()

        let result = try service.moving(id: img.id, to: CanvasPosition(x: 7, y: 9), in: state(images: [img]))

        XCTAssertEqual(result.images.first?.position, CanvasPosition(x: 7, y: 9))
    }

    // MARK: - resizing (aspect-ratio preserved)

    func testResizing_derivesHeightFromWidthAndAspectRatio() throws {
        let img = image(ratio: 2)  // width ÷ height == 2

        let result = try service.resizing(
            id: img.id,
            to: ImagePlacement(position: .zero, size: ImageSize(width: 300, height: 999)),
            in: state(images: [img])
        )

        // Height ignores the supplied 999 and follows width / ratio (300 / 2 == 150).
        XCTAssertEqual(result.images.first?.size, ImageSize(width: 300, height: 150))
    }

    func testResizing_updatesCentre() throws {
        let img = image(ratio: 2)

        let result = try service.resizing(
            id: img.id,
            to: ImagePlacement(position: CanvasPosition(x: 42, y: 43), size: ImageSize(width: 300, height: 150)),
            in: state(images: [img])
        )

        XCTAssertEqual(result.images.first?.position, CanvasPosition(x: 42, y: 43))
    }

    // MARK: - z-order (shared with stickies + shapes)

    func testBringingToFront_liftsAboveAFrontmostSticky() throws {
        let cardID = UUID()
        let img = image(cardID: cardID, sortIndex: 0)
        let sticky = Sticky(cardID: cardID, content: "a", position: .zero, sortIndex: 5)

        let result = try service.bringingToFront(id: img.id, in: state(stickies: [sticky], images: [img]))

        XCTAssertEqual(result.images.first?.sortIndex, 6)
    }

    func testSendingToBack_dropsBelowABackmostShape() throws {
        let cardID = UUID()
        let img = image(cardID: cardID, sortIndex: 0)
        let shape = CanvasShape(cardID: cardID, kind: "rectangle", position: .zero, sortIndex: -2)

        let result = try service.sendingToBack(id: img.id, in: state(shapes: [shape], images: [img]))

        XCTAssertEqual(result.images.first?.sortIndex, -3)
    }

    // MARK: - deleting

    func testDeleting_removesTheImage() throws {
        let img = image()

        let result = try service.deleting(id: img.id, from: state(images: [img]))

        XCTAssertTrue(result.images.isEmpty)
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()

        XCTAssertThrowsError(try service.deleting(id: missingID, from: state(images: []))) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Image", id: missingID))
        }
    }

    // MARK: - fittedImage

    func testFittedImage_scalesLargeImageDownToMaxSidePreservingRatio() {
        // 1000×500 (ratio 2) fits its longer side to 360 → 360×180.
        let fitted = service.fittedImage(naturalSize: NaturalSize(width: 1000, height: 500))

        XCTAssertEqual(fitted.size,
                       ImageSize(width: ImageSize.defaultMaxSide, height: ImageSize.defaultMaxSide / 2))
    }

    func testFittedImage_keepsSmallImageAtNaturalSize() {
        // 100×50 is already under the cap — keep it as-is.
        let fitted = service.fittedImage(naturalSize: NaturalSize(width: 100, height: 50))

        XCTAssertEqual(fitted.size, ImageSize(width: 100, height: 50))
    }

    func testFittedImage_reportsSourceAspectRatio() {
        let fitted = service.fittedImage(naturalSize: NaturalSize(width: 1000, height: 500))

        XCTAssertEqual(fitted.aspectRatio, 2, accuracy: 0.0001)
    }
}
