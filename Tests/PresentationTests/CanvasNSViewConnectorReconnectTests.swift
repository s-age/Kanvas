import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the connector-reconnect gesture (ticket 1C8A0649):
/// - `connectorEndpointHandleHit` — the endpoint-handle hit test that arms a reconnect drag, shown
///   only for a *solely-selected* connector, at each endpoint's live edge midpoint.
/// - `commitConnectorReconnect` — the mouse-up commit, with its two snap-back branches (an empty
///   drop and a self-loop drop) that must fire NO `reconnectConnector` action yet still force a
///   redraw (`needsDisplay`) so the in-progress preview line is erased — the regression behind
///   review finding r1-1, which a headless test now pins.
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity here: world
/// coordinates and view coordinates coincide, which keeps the hit-test points easy to reason about.
@MainActor
final class CanvasNSViewConnectorReconnectTests: XCTestCase {

    private var view: CanvasNSView!
    private var actions: SpyCanvasActionHandler!
    private let sourceID = UUID()
    private let targetID = UUID()
    private let thirdID = UUID()
    private let connectorID = UUID()

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
        actions = SpyCanvasActionHandler()
        view.actions = actions
    }

    override func tearDown() {
        view = nil
        actions = nil
        super.tearDown()
    }

    // MARK: - connectorEndpointHandleHit

    func testEndpointHandleHit_onSelectedConnectorSourceMidpoint_returnsSourceSide() {
        pushScene(selecting: connectorID)
        // Source sticky centred at (-200, 0), 100×80 → right-edge midpoint world == (-150, 0).
        let hit = view.connectorEndpointHandleHit(atView: CGPoint(x: -150, y: 0))

        XCTAssertEqual(hit?.connectorID, connectorID)
        XCTAssertEqual(hit?.side, .source)
    }

    func testEndpointHandleHit_onSelectedConnectorTargetMidpoint_returnsTargetSide() {
        pushScene(selecting: connectorID)
        // Target sticky centred at (200, 0), 100×80 → left-edge midpoint world == (150, 0).
        let hit = view.connectorEndpointHandleHit(atView: CGPoint(x: 150, y: 0))

        XCTAssertEqual(hit?.side, .target)
    }

    func testEndpointHandleHit_awayFromAnyHandle_returnsNil() {
        pushScene(selecting: connectorID)

        XCTAssertNil(view.connectorEndpointHandleHit(atView: CGPoint(x: 0, y: 0)))
    }

    func testEndpointHandleHit_whenConnectorNotSelected_returnsNil() {
        // No sole-selected connector → no endpoint handles are shown, so nothing can be hit.
        pushScene(selecting: nil)

        XCTAssertNil(view.connectorEndpointHandleHit(atView: CGPoint(x: -150, y: 0)))
    }

    // MARK: - commitConnectorReconnect — happy path

    func testCommit_droppingOnAThirdSticky_firesReconnectForThatSide() {
        pushScene(selecting: connectorID)
        // Drag the source end onto a third sticky's centre (0, 300) — neither current endpoint.
        let draft = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 0, y: 300))

        view.commitConnectorReconnect(draft)

        XCTAssertEqual(actions.reconnectGestures.count, 1)
        XCTAssertEqual(actions.reconnectGestures.first?.side, .source)
        XCTAssertEqual(actions.reconnectGestures.first?.newStickyID, thirdID)
    }

    // MARK: - commitConnectorReconnect — manual edge aim (A9B7576E)

    // The third sticky is centred at (0, 300), 100×80 → halfW 50, halfH 40, so the centred
    // dead-zone is ±25 x / ±20 y. A drop past the dead-zone in a quadrant aims at that edge; a
    // central drop falls back to the automatic nearest-to-other-end choice.

    func testCommit_dropAimedAtRightEdge_attachesRight() {
        pushScene(selecting: connectorID)
        // (40, 300): dx 40 dominates dy 0, well past the x dead-zone → right edge.
        let draft = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 40, y: 300))

        view.commitConnectorReconnect(draft)

        XCTAssertEqual(actions.reconnectGestures.first?.newEdge, CanvasEdge.right.rawValue)
    }

    func testCommit_dropAimedAtTopEdge_attachesTop() {
        pushScene(selecting: connectorID)
        // (0, 270): dy -30 dominates dx 0, past the y dead-zone; flipped view → top edge.
        let draft = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 0, y: 270))

        view.commitConnectorReconnect(draft)

        XCTAssertEqual(actions.reconnectGestures.first?.newEdge, CanvasEdge.top.rawValue)
    }

    func testCommit_dropInCentreDeadZone_fallsBackToAutomaticEdge() {
        pushScene(selecting: connectorID)
        // (0, 300) is the sticky centre — inside the dead-zone, so the automatic nearest-to-other
        // choice stands. The other end is source.right's midpoint at (-150, 0); among the third
        // sticky's edge midpoints (top (0,260), bottom (0,340), left (-50,300), right (50,300)) the
        // top midpoint is closest to (-150, 0), so the fallback picks top.
        let draft = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 0, y: 300))

        view.commitConnectorReconnect(draft)

        XCTAssertEqual(actions.reconnectGestures.first?.newEdge, CanvasEdge.top.rawValue)
    }

    // MARK: - commitConnectorReconnect — snap-back branches (r1-1)

    // These snap-back branches are exactly where review finding r1-1 lived. The fix layers a
    // `needsDisplay = true` on top of "fire no action" so the stale preview line is erased — but an
    // unhosted `NSView` (no window/layer) never tracks `needsDisplay`, so it cannot be asserted
    // headlessly. What IS observable, and is the contract these branches must hold, is that no
    // `reconnectConnector` action fires.

    func testCommit_emptyDrop_firesNoReconnect() {
        pushScene(selecting: connectorID)
        // (0, 0) sits between the stickies — on no sticky → empty drop.
        let draft = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 0, y: 0))

        view.commitConnectorReconnect(draft)

        XCTAssertTrue(actions.reconnectGestures.isEmpty)
    }

    func testCommit_selfLoopDropOntoOwnOtherEnd_firesNoReconnect() {
        pushScene(selecting: connectorID)
        // Drag the source end onto the connector's own *target* sticky (200, 0): both ends would then
        // share targetID → self-loop, so snap back.
        let selfLoop = ConnectorReconnectDraft(
            connectorID: connectorID, side: .source, currentWorld: CGPoint(x: 200, y: 0))

        view.commitConnectorReconnect(selfLoop)

        XCTAssertTrue(actions.reconnectGestures.isEmpty,
                      "Dropping an end onto the connector's own other end is a self-loop → snap back")
    }

    func testCommit_selfLoopDropFromTargetEnd_firesNoReconnect() {
        pushScene(selecting: connectorID)
        // Drag the target end onto the connector's own *source* sticky (-200, 0) → self-loop.
        let selfLoop = ConnectorReconnectDraft(
            connectorID: connectorID, side: .target, currentWorld: CGPoint(x: -200, y: 0))

        view.commitConnectorReconnect(selfLoop)

        XCTAssertTrue(actions.reconnectGestures.isEmpty)
    }

    // MARK: - waypoint gesture: hit-test -> draft -> commit (r2-2)

    // The reconnect scene's connector is `.straight` (no waypoint handle); these use an elbow
    // connector so the central deformation handle exists. Base = midpoint of source.right (-150,0)
    // and target.left (150,0) = (0,0), so a handle dragged to world (x,y) commits offset (x,y).

    func testWaypointHandleHit_onSelectedElbowConnectorCentre_returnsConnectorID() {
        pushElbowScene(selecting: connectorID)
        // No waypoint set yet → handle sits at the elbow's geometric centre, the route midpoint (0,0).
        let hit = view.connectorWaypointHandleHit(atView: CGPoint(x: 0, y: 0))

        XCTAssertEqual(hit, connectorID)
    }

    func testWaypointHandleHit_whenConnectorNotSelected_returnsNil() {
        pushElbowScene(selecting: nil)

        XCTAssertNil(view.connectorWaypointHandleHit(atView: CGPoint(x: 0, y: 0)))
    }

    func testCommitWaypoint_firesSetConnectorWaypointWithDraggedOffset() {
        pushElbowScene(selecting: connectorID)
        // Drag the handle to world (50, 80); base is (0,0) so the committed offset is (50, 80).
        let draft = ConnectorWaypointDraft(
            connectorID: connectorID, currentWorld: CGPoint(x: 50, y: 80))

        view.commitConnectorWaypoint(draft)

        XCTAssertEqual(actions.waypointEdits.count, 1)
    }

    func testCommitWaypoint_committedOffsetMatchesHandlePositionRelativeToBasis() {
        pushElbowScene(selecting: connectorID)
        let draft = ConnectorWaypointDraft(
            connectorID: connectorID, currentWorld: CGPoint(x: 50, y: 80))

        view.commitConnectorWaypoint(draft)

        let edit = actions.waypointEdits.first
        XCTAssertEqual(edit?.id, connectorID)
        XCTAssertEqual(edit?.offsetX ?? .nan, 50, accuracy: 0.001)
        XCTAssertEqual(edit?.offsetY ?? .nan, 80, accuracy: 0.001)
    }

    // MARK: - Helpers

    /// Like `pushScene` but the connector routes `.elbow`, so it carries a central waypoint
    /// deformation handle (a `.straight` connector has none). Only the source and target stickies
    /// are needed here.
    private func pushElbowScene(selecting selectedID: UUID?) {
        let source = stickyFixture(id: sourceID, centerX: -200, centerY: 0)
        let target = stickyFixture(id: targetID, centerX: 200, centerY: 0)
        let connector = ConnectorResponse(
            id: connectorID, sourceStickyID: sourceID, sourceEdge: .right,
            targetStickyID: targetID, targetEdge: .left,
            cap: .arrow, routing: .elbow, strokeColorHex: nil,
            strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
            waypointOffsetX: nil, waypointOffsetY: nil
        )
        view.update(
            CanvasContent(stickies: [source, target], shapes: [], images: [], texts: [], connectors: [connector]),
            selectedIDs: selectedID.map { [$0] } ?? [], settings: nil, global: nil
        )
    }

    /// Pushes a three-sticky + one-connector scene and selects `connectorID` (or nothing). Source
    /// sticky sits at (-200, 0), target at (200, 0), a free third sticky at (0, 300); the connector
    /// links source.right → target.left. The third sticky is the reconnect drop target the source
    /// end can legally move to (neither current endpoint, so no self-loop).
    private func pushScene(selecting selectedID: UUID?) {
        let source = stickyFixture(id: sourceID, centerX: -200, centerY: 0)
        let target = stickyFixture(id: targetID, centerX: 200, centerY: 0)
        let third = stickyFixture(id: thirdID, centerX: 0, centerY: 300)
        let connector = ConnectorResponse(
            id: connectorID, sourceStickyID: sourceID, sourceEdge: .right,
            targetStickyID: targetID, targetEdge: .left,
            cap: .arrow, routing: .straight, strokeColorHex: nil,
            strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
            waypointOffsetX: nil, waypointOffsetY: nil
        )
        view.update(
            CanvasContent(stickies: [source, target, third], shapes: [], images: [], texts: [], connectors: [connector]),
            selectedIDs: selectedID.map { [$0] } ?? [], settings: nil, global: nil
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
// Captures the reconnect gestures the commit emits; every other action is a no-op. The canvas
// routes all state changes through `CanvasActionHandler`, so a spy at that seam is the headless
// observation point — no ViewModel / DI stack needed.

@MainActor
private final class SpyCanvasActionHandler: CanvasActionHandler {

    private(set) var reconnectGestures: [ConnectorReconnectGesture] = []
    private(set) var waypointEdits: [(id: UUID, offsetX: Double, offsetY: Double)] = []

    func reconnectConnector(_ gesture: ConnectorReconnectGesture) {
        reconnectGestures.append(gesture)
    }

    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) {
        waypointEdits.append((id, offsetX, offsetY))
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
    func growConnector(_ gesture: ConnectorGrowGesture) {}
    func selectConnector(id: UUID?) {}
    func deleteConnector(id: UUID) {}
}
