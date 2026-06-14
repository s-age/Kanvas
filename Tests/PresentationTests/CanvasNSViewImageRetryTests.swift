import AppKit
import XCTest
@testable import KanvasCore

/// The canvas-side half of ticket 37B774CD's image-load policy: the consecutive-transient-failure
/// counter (`transientImageLoadAttempts`) in `CanvasNSView.loadImageIfNeeded`. The classifier half
/// (`BoardViewModel.loadImageData`'s error → `CanvasImageLoad` mapping) is pinned by
/// `BoardViewModelImageLoadTests`; this pins the count → terminal-promotion the canvas layers on top.
///
/// `loadImageIfNeeded` returns its spawned `Task` purely so these tests can await the fetch and its
/// state mutations deterministically — production fire-and-forgets it.
@MainActor
final class CanvasNSViewImageRetryTests: XCTestCase {

    private var view: CanvasNSView!
    private var actions: MockCanvasActionHandler!

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
        actions = MockCanvasActionHandler()
        view.actions = actions
    }

    override func tearDown() {
        view = nil
        actions = nil
        super.tearDown()
    }

    // MARK: - Transient failure under the retry limit

    func testTransientFailure_underLimit_incrementsAttemptCounter() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await view.loadImageIfNeeded(assetID: assetID)?.value

        XCTAssertEqual(view.transientImageLoadAttempts[assetID], 1)
    }

    func testTransientFailure_underLimit_isNotNegativeCached() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await view.loadImageIfNeeded(assetID: assetID)?.value

        XCTAssertFalse(view.failedImageLoads.contains(assetID))
    }

    func testTransientFailure_underLimit_isNotReported() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await view.loadImageIfNeeded(assetID: assetID)?.value

        XCTAssertTrue(actions.reportedFailures.isEmpty)
    }

    func testTransientFailure_underLimit_nextRedrawRefetches() async {
        // Not negative-cached → the guard doesn't short-circuit, so a redraw starts a fresh fetch.
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()
        await view.loadImageIfNeeded(assetID: assetID)?.value

        let secondFetch = view.loadImageIfNeeded(assetID: assetID)

        XCTAssertNotNil(secondFetch, "A non-cached transient failure should be retried, not blocked")
        await secondFetch?.value
    }

    // MARK: - Promotion to terminal at the retry limit

    func testTransientFailure_atLimit_isNegativeCached() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await driveTransientFailuresToLimit(assetID: assetID)

        XCTAssertTrue(view.failedImageLoads.contains(assetID))
    }

    func testTransientFailure_atLimit_clearsAttemptCounter() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await driveTransientFailuresToLimit(assetID: assetID)

        XCTAssertNil(view.transientImageLoadAttempts[assetID])
    }

    func testTransientFailure_atLimit_reportsUnreadableExactlyOnce() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()

        await driveTransientFailuresToLimit(assetID: assetID)

        XCTAssertEqual(actions.reportedFailures.count, 1)
        guard case .unreadable = actions.reportedFailures.first?.reason else {
            return XCTFail("Expected the cap promotion to report .unreadable")
        }
    }

    func testTransientFailure_pastLimit_stopsRefetching() async {
        // Once negative-cached, the guard short-circuits and no further fetch Task is spawned.
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()
        await driveTransientFailuresToLimit(assetID: assetID)

        let blockedFetch = view.loadImageIfNeeded(assetID: assetID)

        XCTAssertNil(blockedFetch, "A negative-cached asset must not be re-fetched on later redraws")
    }

    // MARK: - Counter cleared by success and by leaving the canvas

    func testLoadedAfterTransientFailures_clearsAttemptCounter() async {
        // Two transients (attempts == 2, under the limit), then bytes arrive → counter resets.
        actions.imageLoadOutcomes = [.transientFailure, .transientFailure, .loaded(makePNGData())]
        let assetID = UUID()

        await view.loadImageIfNeeded(assetID: assetID)?.value
        await view.loadImageIfNeeded(assetID: assetID)?.value
        await view.loadImageIfNeeded(assetID: assetID)?.value

        XCTAssertNil(view.transientImageLoadAttempts[assetID])
    }

    func testImageLeavingCanvas_clearsAttemptCounter() async {
        actions.imageLoadOutcomes = [.transientFailure]
        let assetID = UUID()
        push(images: [makeImageResponse(assetID: assetID)])
        await view.loadImageIfNeeded(assetID: assetID)?.value
        XCTAssertEqual(view.transientImageLoadAttempts[assetID], 1, "precondition: a transient attempt is recorded")

        push(images: [])  // the image is removed from the card's canvas

        XCTAssertNil(view.transientImageLoadAttempts[assetID])
    }

    // MARK: - Helpers

    /// Runs `loadImageIfNeeded` `transientImageLoadRetryLimit` times, awaiting each fetch — driving a
    /// persistently-transient asset exactly to the promotion threshold.
    private func driveTransientFailuresToLimit(assetID: UUID) async {
        for _ in 0..<CanvasNSView.transientImageLoadRetryLimit {
            await view.loadImageIfNeeded(assetID: assetID)?.value
        }
    }

    private func push(images: [ImageResponse]) {
        view.update(
            CanvasContent(stickies: [], shapes: [], images: images, texts: [], connectors: []),
            selectedIDs: [], settings: nil, global: nil
        )
    }
}

// MARK: - Fixtures

private func makeImageResponse(assetID: UUID) -> ImageResponse {
    ImageResponse(
        id: UUID(), assetID: assetID, positionX: 0, positionY: 0, width: 100, height: 100,
        minWidth: 10, minHeight: 10, maxWidth: 1000, maxHeight: 1000, aspectRatio: 1, sortIndex: 0
    )
}

/// A minimal but genuinely decodable 1×1 PNG, so the `.loaded` path reaches `NSImage(data:)` success
/// (and thus the counter-clearing branch) rather than the undecodable-data terminal branch.
private func makePNGData() -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
    )!
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - Mock action handler
//
// The canvas routes every state change through `CanvasActionHandler`; only `imageData` (the fetch
// seam) and `reportImageLoadFailure` (the diagnostics seam) matter here, so the rest are no-ops.

@MainActor
private final class MockCanvasActionHandler: CanvasActionHandler {

    /// Outcomes returned by `imageData`, consumed in order; the last repeats once exhausted (so a
    /// single `[.transientFailure]` drives an unbounded retry sequence).
    var imageLoadOutcomes: [CanvasImageLoad] = [.transientFailure]
    private(set) var reportedFailures: [(assetID: UUID, reason: ImageLoadFailureReason)] = []
    private var imageDataCallCount = 0

    func imageData(assetID: UUID) async -> CanvasImageLoad {
        defer { imageDataCallCount += 1 }
        guard !imageLoadOutcomes.isEmpty else { return .transientFailure }
        return imageLoadOutcomes[min(imageDataCallCount, imageLoadOutcomes.count - 1)]
    }

    func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason) {
        reportedFailures.append((assetID, reason))
    }

    // Unused by these tests — no-ops to satisfy the protocol.
    func addSticky(worldX: Double, worldY: Double, presetID: UUID) {}
    func moveSticky(id: UUID, worldX: Double, worldY: Double) {}
    func setStickyFrame(id: UUID, worldFrame: CGRect) {}
    func selectSticky(id: UUID?) {}
    func toggleSelection(id: UUID) {}
    func selectRegion(ids: Set<UUID>, additive: Bool) {}
    func moveSelected(_ moves: [CanvasDragMove]) {}
    func deleteSelected(ids: [UUID]) {}
    func editSticky(id: UUID, content: String) {}
    func deleteSticky(id: UUID) {}
    func copySticky(id: UUID) {}
    func pasteSticky() {}
    func bringStickyToFront(id: UUID) {}
    func sendStickyToBack(id: UUID) {}
    func openLabelManager(stickyID: UUID) {}
    func undo() {}
    func addShape(_ draft: ShapeDraft) {}
    func moveShape(id: UUID, worldX: Double, worldY: Double) {}
    func resizeShape(id: UUID, worldFrame: CGRect, lineRising: Bool?) {}
    func selectShape(id: UUID?) {}
    func deleteShape(id: UUID) {}
    func bringShapeToFront(id: UUID) {}
    func sendShapeToBack(id: UUID) {}
    func addImage(worldX: Double, worldY: Double, payload: CanvasImagePayload) {}
    func moveImage(id: UUID, worldX: Double, worldY: Double) {}
    func resizeImage(id: UUID, worldFrame: CGRect) {}
    func selectImage(id: UUID?) {}
    func deleteImage(id: UUID) {}
    func bringImageToFront(id: UUID) {}
    func sendImageToBack(id: UUID) {}
    func addText(worldX: Double, worldY: Double) {}
    func copyText(id: UUID) {}
    func pasteText() {}
    func editText(id: UUID, content: String) {}
    func moveText(id: UUID, worldX: Double, worldY: Double) {}
    func setTextFrame(id: UUID, worldFrame: CGRect) {}
    func selectText(id: UUID?) {}
    func deleteText(id: UUID) {}
    func bringTextToFront(id: UUID) {}
    func sendTextToBack(id: UUID) {}
    func growConnector(_ gesture: ConnectorGrowGesture) {}
    func selectConnector(id: UUID?) {}
    func reconnectConnector(_ gesture: ConnectorReconnectGesture) {}
    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) {}
    func deleteConnector(id: UUID) {}
}
