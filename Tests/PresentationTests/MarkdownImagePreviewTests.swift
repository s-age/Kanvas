import XCTest
@testable import KanvasCore

/// Tests for the pure pieces of the resizable Markdown image-preview window (ticket 8511D150):
/// `MarkdownPreviewWindowSizing.initialContentSize` (the aspect-fit-into-80%-of-board initial size)
/// and `MarkdownImagePreviewRequest.currentAssetID` (the index→asset resolution that the future
/// Lightbox navigation, ticket B23D376B, will step).
final class MarkdownImagePreviewTests: XCTestCase {

    // MARK: - initialContentSize

    /// A landscape image larger than the budget is shrunk to touch 80% of the board width while
    /// preserving its aspect ratio (height comes out below the 80% height cap).
    func testLandscapeImageFitsToEightyPercentWidth() {
        let size = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: CGSize(width: 2000, height: 1000),
            budget: CGSize(width: 1000, height: 1000)
        )
        // 80% of 1000 width = 800; aspect 2:1 → height 400.
        XCTAssertEqual(size.width, 800, accuracy: 0.5)
        XCTAssertEqual(size.height, 400, accuracy: 0.5)
    }

    /// A tall image is bound by the 80% *height* cap, not width (aspect ratio preserved).
    func testPortraitImageFitsToEightyPercentHeight() {
        let size = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: CGSize(width: 500, height: 2000),
            budget: CGSize(width: 1000, height: 1000)
        )
        // 80% of 1000 height = 800; aspect 1:4 → width 200, but the 480 min floor lifts width to 480.
        XCTAssertEqual(size.height, 800, accuracy: 0.5)
        XCTAssertEqual(size.width, 480, accuracy: 0.5)
    }

    /// A small image is *enlarged* to the 80% budget (ticket: 小さい画像も拡大する) — not left at its
    /// intrinsic size.
    func testSmallImageIsEnlargedToBudget() {
        let size = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: CGSize(width: 100, height: 100),
            budget: CGSize(width: 1000, height: 1000)
        )
        // 80% of 1000 = 800 on the bound axis; square aspect → 800×800.
        XCTAssertEqual(size.width, 800, accuracy: 0.5)
        XCTAssertEqual(size.height, 800, accuracy: 0.5)
    }

    /// The result never drops below the 480×360 resize floor, even when 80% of the board is tiny.
    func testClampsUpToMinimumSize() {
        let size = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: CGSize(width: 100, height: 100),
            budget: CGSize(width: 200, height: 200)
        )
        XCTAssertEqual(size.width, MarkdownPreviewWindowSizing.minimumContentSize.width, accuracy: 0.5)
        XCTAssertEqual(size.height, MarkdownPreviewWindowSizing.minimumContentSize.height, accuracy: 0.5)
    }

    /// A degenerate intrinsic size (zero dimension) or unavailable board budget falls back to the
    /// minimum size rather than producing a zero/NaN frame.
    func testDegenerateInputsFallBackToMinimum() {
        let zeroImage = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: .zero, budget: CGSize(width: 1000, height: 1000))
        XCTAssertEqual(zeroImage, MarkdownPreviewWindowSizing.minimumContentSize)

        let zeroBudget = MarkdownPreviewWindowSizing.initialContentSize(
            intrinsicSize: CGSize(width: 800, height: 600), budget: .zero)
        XCTAssertEqual(zeroBudget, MarkdownPreviewWindowSizing.minimumContentSize)
    }

    // MARK: - currentAssetID

    func testCurrentAssetIDResolvesIndex() {
        let ids = [UUID(), UUID(), UUID()]
        let request = MarkdownImagePreviewRequest(
            assetIDs: ids, currentIndex: 1, boardWindowSize: .zero, generation: 1)
        XCTAssertEqual(request.currentAssetID, ids[1])
    }

    func testCurrentAssetIDIsNilWhenIndexOutOfRange() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID()], currentIndex: 5, boardWindowSize: .zero, generation: 1)
        XCTAssertNil(request.currentAssetID)
    }

    func testCurrentAssetIDIsNilWhenEmpty() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [], currentIndex: 0, boardWindowSize: .zero, generation: 1)
        XCTAssertNil(request.currentAssetID)
    }

    // MARK: - hasPrevious / hasNext (Lightbox navigation gating, ticket B23D376B)

    func testHasPreviousIsFalseAtFirstIndex() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID(), UUID()], currentIndex: 0, boardWindowSize: .zero, generation: 1)
        XCTAssertFalse(request.hasPrevious)
    }

    func testHasNextIsTrueAtFirstIndexWithMore() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID(), UUID()], currentIndex: 0, boardWindowSize: .zero, generation: 1)
        XCTAssertTrue(request.hasNext)
    }

    func testHasNextIsFalseAtLastIndex() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID(), UUID()], currentIndex: 1, boardWindowSize: .zero, generation: 1)
        XCTAssertFalse(request.hasNext)
    }

    func testHasPreviousIsTrueAtLastIndex() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID(), UUID()], currentIndex: 1, boardWindowSize: .zero, generation: 1)
        XCTAssertTrue(request.hasPrevious)
    }

    func testSingleAssetHasNeitherNeighbour() {
        let request = MarkdownImagePreviewRequest(
            assetIDs: [UUID()], currentIndex: 0, boardWindowSize: .zero, generation: 1)
        XCTAssertFalse(request.hasPrevious)
        XCTAssertFalse(request.hasNext)
    }

    // MARK: - stepMarkdownImagePreview (Lightbox index stepping, ticket B23D376B)

    @MainActor
    func testStepForwardAdvancesToNextAsset() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID(), UUID()]
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: .zero)

        vm.stepMarkdownImagePreview(by: 1)

        XCTAssertEqual(vm.markdownImagePreview?.currentAssetID, ids[1])
    }

    @MainActor
    func testStepBackwardReturnsToPreviousAsset() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID(), UUID()]
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 2, boardWindowSize: .zero)

        vm.stepMarkdownImagePreview(by: -1)

        XCTAssertEqual(vm.markdownImagePreview?.currentAssetID, ids[1])
    }

    @MainActor
    func testStepPastLastIsNoOp() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID()]
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 1, boardWindowSize: .zero)
        let before = vm.markdownImagePreview

        vm.stepMarkdownImagePreview(by: 1)

        XCTAssertEqual(vm.markdownImagePreview, before)
    }

    @MainActor
    func testStepBeforeFirstIsNoOp() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID()]
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: .zero)
        let before = vm.markdownImagePreview

        vm.stepMarkdownImagePreview(by: -1)

        XCTAssertEqual(vm.markdownImagePreview, before)
    }

    @MainActor
    func testStepPreservesAssetIDsAndBoardWindowSize() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID()]
        let board = CGSize(width: 1000, height: 800)
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: board)

        vm.stepMarkdownImagePreview(by: 1)

        XCTAssertEqual(vm.markdownImagePreview?.assetIDs, ids)
        XCTAssertEqual(vm.markdownImagePreview?.boardWindowSize, board)
    }

    @MainActor
    func testStepProducesDistinctGeneration() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID()]
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: .zero)
        let firstGeneration = vm.markdownImagePreview?.generation

        vm.stepMarkdownImagePreview(by: 1)

        XCTAssertNotEqual(vm.markdownImagePreview?.generation, firstGeneration)
    }

    @MainActor
    func testStepWithNoOpenPreviewIsNoOp() {
        let vm = makeBoardViewModel()
        vm.stepMarkdownImagePreview(by: 1)
        XCTAssertNil(vm.markdownImagePreview)
    }

    // MARK: - generation (decoupled-close reopen race, ticket 8511D150)

    /// Two opens of the *same* image, index, and (unmoved) board window still differ — the monotonic
    /// `generation` stamp distinguishes them. This is what lets the closing window's identity-gated
    /// teardown tell an in-flight close apart from a same-thumbnail reopen during the dismiss
    /// animation, so the reopened window is not wiped blank.
    @MainActor
    func testReopeningSameImageProducesDistinctRequest() {
        let vm = makeBoardViewModel()
        let ids = [UUID(), UUID()]
        let board = CGSize(width: 1000, height: 800)

        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: board)
        let first = vm.markdownImagePreview
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: board)
        let second = vm.markdownImagePreview

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first?.currentAssetID, second?.currentAssetID)
    }

    /// The identity-gated teardown clears the shared state only when it still matches the snapshot the
    /// closing window owned — the ordinary close with no reopen.
    @MainActor
    func testClearIfMatchingClearsWhenSnapshotIsCurrent() {
        let vm = makeBoardViewModel()
        vm.openMarkdownImagePreview(assetIDs: [UUID()], currentIndex: 0, boardWindowSize: .zero)
        let snapshot = vm.markdownImagePreview

        vm.clearMarkdownImagePreview(ifMatching: snapshot)

        XCTAssertNil(vm.markdownImagePreview)
    }

    /// A same-image reopen during the dismiss animation advances `generation`, so the stale teardown's
    /// snapshot no longer matches the live request and the gate leaves the reopened target intact —
    /// the empty-window race the round-3 finding flagged.
    @MainActor
    func testClearIfMatchingLeavesReopenedTargetIntact() {
        let vm = makeBoardViewModel()
        let ids = [UUID()]

        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: .zero)
        let staleSnapshot = vm.markdownImagePreview          // the closing window's snapshot
        vm.openMarkdownImagePreview(assetIDs: ids, currentIndex: 0, boardWindowSize: .zero)
        let reopened = vm.markdownImagePreview               // same image, reopened mid-animation

        vm.clearMarkdownImagePreview(ifMatching: staleSnapshot)

        XCTAssertEqual(vm.markdownImagePreview, reopened)
    }
}
