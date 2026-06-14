import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the connector-**grow** gesture's edge decision (ticket 2D72DA61):
/// `commitConnectorDraft` (`CanvasNSView+Connectors`) now applies the same manual-aim →
/// automatic-fallback edge choice that reconnect uses (`aimedEdge`, +ConnectorReconnect) when a grow
/// drop lands on an existing sticky. A drop in an edge's outer band honours that edge; a central drop
/// falls back to the automatic `nearestEdge`-to-source choice (the prior, behaviour-preserving path).
/// The empty-canvas branch (growing a brand-new sticky) is unchanged — it still uses `edgeFacing`,
/// since the new sticky's rect is not yet known — and is pinned here so that path keeps its arg shape.
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity here: world
/// and view coordinates coincide, keeping the drop points easy to reason about.
@MainActor
final class CanvasNSViewConnectorGrowAimedEdgeTests: XCTestCase {

    private var view: CanvasNSView!
    private var actions: SpyGrowActionHandler!
    private let sourceID = UUID()
    private let targetID = UUID()

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
        actions = SpyGrowActionHandler()
        view.actions = actions
    }

    override func tearDown() {
        view = nil
        actions = nil
        super.tearDown()
    }

    // MARK: - commitConnectorDraft — drop on an existing sticky: manual aim

    // The target sticky is centred at (200, 0), 100×80 → halfW 50, halfH 40, so the centred dead-zone
    // is ±25 x / ±20 y. A drop past the dead-zone in a quadrant aims at that edge; a central drop
    // falls back to the automatic nearest-to-source choice.

    func testCommit_dropAimedAtRightEdge_attachesRight() {
        pushScene()
        // (240, 0): dx +40 from the target centre dominates dy 0, past the x dead-zone → right edge.
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 240, y: 0))

        view.commitConnectorDraft(draft)

        XCTAssertEqual(actions.growGestures.first?.targetEdge, CanvasEdge.right.rawValue)
    }

    func testCommit_dropAimedAtBottomEdge_attachesBottom() {
        pushScene()
        // (200, 30): dy +30 from the target centre dominates dx 0, past the y dead-zone; flipped
        // view (y grows downward) → bottom edge.
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 200, y: 30))

        view.commitConnectorDraft(draft)

        XCTAssertEqual(actions.growGestures.first?.targetEdge, CanvasEdge.bottom.rawValue)
    }

    func testCommit_dropOnExistingSticky_targetsThatSticky() {
        pushScene()
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 240, y: 0))

        view.commitConnectorDraft(draft)

        XCTAssertEqual(actions.growGestures.first?.existingTargetStickyID, targetID)
    }

    // MARK: - commitConnectorDraft — central drop: automatic fallback (behaviour-preserving)

    func testCommit_dropInCentreDeadZone_fallsBackToAutomaticEdge() {
        pushScene()
        // (200, 0) is the target sticky centre — inside the dead-zone, so the automatic
        // nearest-to-source choice stands. The source.right midpoint is (-150, 0); among the target's
        // edge midpoints (top (200,-40), bottom (200,40), left (150,0), right (250,0)) the left
        // midpoint is closest to (-150, 0), so the fallback picks left — the prior behaviour.
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 200, y: 0))

        view.commitConnectorDraft(draft)

        XCTAssertEqual(actions.growGestures.first?.targetEdge, CanvasEdge.left.rawValue)
    }

    // MARK: - commitConnectorDraft — empty canvas: unchanged edgeFacing path

    func testCommit_dropOnEmptyCanvas_growsNewStickyWithNoExistingTarget() {
        pushScene()
        // (600, 0) is empty canvas (no sticky there) → grow a new sticky, no existing target id.
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 600, y: 0))

        view.commitConnectorDraft(draft)

        XCTAssertNil(actions.growGestures.first?.existingTargetStickyID)
    }

    func testCommit_dropOnEmptyCanvas_facesSource() {
        pushScene()
        // New sticky centred at (600, 0); source.right midpoint is (-150, 0) to its left → the new
        // sticky's left edge faces the source (edgeFacing, dominant -x).
        let draft = ConnectorDraft(
            sourceStickyID: sourceID, sourceEdge: .right, currentWorld: CGPoint(x: 600, y: 0))

        view.commitConnectorDraft(draft)

        XCTAssertEqual(actions.growGestures.first?.targetEdge, CanvasEdge.left.rawValue)
    }

    // MARK: - Helpers

    /// Pushes a two-sticky scene: the grow source at (-200, 0) and an existing target sticky at
    /// (200, 0), both 100×80. No selection is needed — `commitConnectorDraft` reads the draft, not the
    /// selection.
    private func pushScene() {
        let source = stickyFixture(id: sourceID, centerX: -200, centerY: 0)
        let target = stickyFixture(id: targetID, centerX: 200, centerY: 0)
        view.update(
            CanvasContent(stickies: [source, target], shapes: [], images: [], texts: [], connectors: []),
            selectedIDs: [], settings: nil, global: nil
        )
    }
}

// MARK: - Fixtures

private func stickyFixture(id: UUID, centerX: Double, centerY: Double) -> StickyResponse {
    StickyResponse(
        id: id, content: "", isTask: false, linkedCardTitle: nil,
        positionX: centerX, positionY: centerY, width: 100, height: 80,
        minWidth: 40, minHeight: 40, maxWidth: 400, maxHeight: 400,
        textColorHex: "000000", fontSize: 13, fillColorHex: nil, sortIndex: 0, labels: []
    )
}

// MARK: - Spy action handler
//
// Captures the grow gestures the commit emits; every other action is a no-op. The canvas routes all
// state changes through `CanvasActionHandler`, so a spy at that seam is the headless observation
// point — no ViewModel / DI stack needed.

@MainActor
private final class SpyGrowActionHandler: CanvasActionHandler {

    private(set) var growGestures: [ConnectorGrowGesture] = []

    func growConnector(_ gesture: ConnectorGrowGesture) {
        growGestures.append(gesture)
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
    func imageData(assetID: UUID) async -> CanvasImageLoad { .transientFailure }
    func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason) {}
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
    func reconnectConnector(_ gesture: ConnectorReconnectGesture) {}
    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) {}
    func selectConnector(id: UUID?) {}
    func deleteConnector(id: UUID) {}
}
