import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the Phase 2 waypoint rect-clamp (ticket 805F3652 §C / D-5): ruling 5
/// requires a waypoint dropped behind a sticky's edge to commit to the nearest point outside it
/// instead — `clampWaypointOutsideRects` (shared by `commitConnectorWaypoint` and
/// `connectorViewGeometry`'s draw-time re-clamp). Fixed-rect fixtures below are copied verbatim from
/// the card's worked examples (design rounds 4-5), so `clampWaypointOutsideRects` is tested directly
/// against them wherever the assertion doesn't need a live sticky/connector (the card's LOW finding
/// (a): "共有クランプ関数は...そのまま単体テストできる形にする").
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity: world and view
/// coordinates coincide.
@MainActor
final class CanvasNSViewConnectorWaypointClampTests: XCTestCase {

    private var view: CanvasNSView!
    private var actions: SpyCanvasActionHandler!
    private let sourceID = UUID()
    private let targetID = UUID()
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

    // MARK: - Pure clamp function, direct (card's fixed-rect fixtures)

    func testClamp_pointInsideOneRect_pushesOutsideByMargin() {
        let sourceRect = CGRect(x: -400, y: -40, width: 100, height: 80)
        let targetRect = CGRect(x: 300, y: -40, width: 100, height: 80)
        let clamped = view.clampWaypointOutsideRects(CGPoint(x: -370, y: 0), sourceRect: sourceRect,
                                                      targetRect: targetRect)

        XCTAssertEqual(clamped.x, -420, accuracy: 0.01,
                      "Nearest edge is source's left (x=-400, 30px away vs 70px to the right) - margin 20")
        XCTAssertEqual(clamped.y, 0, accuracy: 0.01)
    }

    func testClamp_twoStepReversal_fallsBackToGapMidpoint() {
        // Card's worked example (§C "2段階クランプの逆戻り→隙間中点フォールバック"): gap (10px) < margin
        // (20px), non-overlapping. The 2-step clamp pushes back into source; the gap-midpoint fallback
        // must recover a point outside both rects.
        let sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let targetRect = CGRect(x: 110, y: 0, width: 190, height: 100)
        let clamped = view.clampWaypointOutsideRects(CGPoint(x: 95, y: 50), sourceRect: sourceRect,
                                                      targetRect: targetRect)

        XCTAssertEqual(clamped.x, 105, accuracy: 0.01, "Separating gap's midpoint: (100+110)/2")
        XCTAssertEqual(clamped.y, 50, accuracy: 0.01)
    }

    func testClamp_overlappingRects_noSeparatingAxis_skipsFallbackWithoutCrashing() {
        // Card's worked example (§C "分離軸なし（矩形が重なる）場合のフォールバック無効化"): the two
        // rects OVERLAP, so no axis separates them; the fallback must skip (not crash), leaving the
        // 2-step clamp's result even though it's still inside source — an accepted "known limitation"
        // for overlapping stickies (out of scope), not a defect.
        let sourceRect = CGRect(x: 0, y: 0, width: 100, height: 100)
        let targetRect = CGRect(x: 90, y: 0, width: 210, height: 100)
        let clamped = view.clampWaypointOutsideRects(CGPoint(x: 95, y: 50), sourceRect: sourceRect,
                                                      targetRect: targetRect)

        XCTAssertEqual(clamped.x, 70, accuracy: 0.01)
        XCTAssertEqual(clamped.y, 50, accuracy: 0.01)
    }

    func testClamp_pointAlreadyOutsideBothRects_isUnchanged() {
        let sourceRect = CGRect(x: -400, y: -40, width: 100, height: 80)
        let targetRect = CGRect(x: 300, y: -40, width: 100, height: 80)
        let point = CGPoint(x: 0, y: 60)

        let clamped = view.clampWaypointOutsideRects(point, sourceRect: sourceRect, targetRect: targetRect)

        XCTAssertEqual(clamped.x, point.x, accuracy: 0.01)
        XCTAssertEqual(clamped.y, point.y, accuracy: 0.01)
    }

    func testClamp_exactCentreTie_breaksLeftPerDeclarationOrder() {
        // All four edge distances are equal (25) at a square rect's exact centre, so `clampOutsideRect`'s
        // `nearest == distLeft` branch (checked first, in source order) must win — pins the tie-break to
        // left/right/top/bottom declaration order (the card's "同点処理" rule) so a later refactor of the
        // if-chain into a `switch`/`Dictionary` can't silently reorder it without this test going red.
        let sourceRect = CGRect(x: 0, y: 0, width: 50, height: 50)
        let targetRect = CGRect(x: 1000, y: 1000, width: 50, height: 50)
        let clamped = view.clampWaypointOutsideRects(CGPoint(x: 25, y: 25), sourceRect: sourceRect,
                                                      targetRect: targetRect)

        XCTAssertEqual(clamped.x, -20, accuracy: 0.01, "Tie resolves to the left edge (declaration order)")
        XCTAssertEqual(clamped.y, 25, accuracy: 0.01)
    }

    // MARK: - D-5: leg avoidance on an already-clamped waypoint (elbowPoints, direct geometry)

    func testWaypointLegs_afterClamp_avoidBothRects() {
        // Fixture found via the design's Python reference (`phase2_waypoint.py`'s `safe_leg`), rounded
        // to 1 decimal and re-verified: the waypoint is already outside both rects (isolating the LEG
        // detour mechanism from the clamp), but the DIRECT leg shapes still cross — §C's per-leg
        // bridge-candidate fallback must clear them.
        let sourceRect = CGRect(x: -156.75, y: -65.3, width: 96.9, height: 87.0)
        let targetRect = CGRect(x: -37.2, y: -247.4, width: 104.6, height: 126.8)
        let waypoint = CGPoint(x: -11.8, y: 26.2)
        let geo = ConnectorViewGeometry(
            start: view.edgeMidpoint(of: sourceRect, edge: .left), end: view.edgeMidpoint(of: targetRect, edge: .right),
            sourceEdge: .left, targetEdge: .right, waypoint: waypoint, sourceRect: sourceRect, targetRect: targetRect
        )
        var bare = geo
        bare.sourceRect = nil
        bare.targetRect = nil

        XCTAssertTrue(view.routeCrossesRects(view.elbowPoints(bare), rects: [sourceRect, targetRect]),
                      "Fixture must actually need leg avoidance (direct legs cross)")
        XCTAssertFalse(view.routeCrossesRects(view.elbowPoints(geo), rects: [sourceRect, targetRect]),
                       "Rect-aware legs must avoid both rects")
    }

    // MARK: - D-5: commit-time clamp (full pipeline via commitConnectorWaypoint) + undo is one step

    func testCommitWaypoint_droppedBehindSourceEdge_clampsBeforeStoringOffset() {
        let connector = makeConnector(offsetX: nil, offsetY: nil)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -200, y: 0), targetCenter: CGPoint(x: 200, y: 0))
        // Source sticky rect (-250,-40)-(-150,40); dropped at (-180,0), inside it.
        let draft = ConnectorWaypointDraft(connectorID: connector.id, currentWorld: CGPoint(x: -180, y: 0))

        view.commitConnectorWaypoint(draft)

        XCTAssertEqual(actions.waypointEdits.count, 1, "commit must write exactly one undo step")
        let edit = actions.waypointEdits[0]
        XCTAssertEqual(edit.id, connector.id)
        // Clamped to source's right edge (x=-150) + margin 20 = -130; basis is the world origin (0,0)
        // (midpoint of the two 100x80 stickies' facing edges at x=-150/x=150).
        XCTAssertEqual(edit.offsetX, -130, accuracy: 0.01,
                      "Stored offset must be computed from the CLAMPED point, not the raw drop point")
        XCTAssertEqual(edit.offsetY, 0, accuracy: 0.01)
    }

    // MARK: - D-5: draw-time re-clamp tracks a moved sticky without rewriting the stored offset

    func testDrawTimeReClamp_targetMovesWaypointInside_reclampsWithoutRewritingStoredOffset() {
        // Card's worked example (§C "描画時の再クランプ"): source rect (0,0,100,100), target initially
        // (300,0,400,100), offset (90,0) -> initial waypoint (290,50), not inside the initial target.
        let connector = makeConnector(offsetX: 90, offsetY: 0)
        pushScene(connector: connector, sourceCenter: CGPoint(x: 50, y: 50), targetCenter: CGPoint(x: 350, y: 50))
        guard let initialWaypoint = view.connectorViewGeometry(connector)?.waypoint else {
            return XCTFail("Expected resolvable geometry")
        }
        XCTAssertEqual(initialWaypoint.x, 290, accuracy: 0.01)
        XCTAssertEqual(initialWaypoint.y, 50, accuracy: 0.01)

        // Move target left by 40 -> new rect (260,0,360,100); the offset's basis moves with it (half
        // the delta, being midpoint-relative), so the raw (re-clamp candidate) waypoint becomes
        // (270,50) -- inside the new target rect.
        pushScene(connector: connector, sourceCenter: CGPoint(x: 50, y: 50), targetCenter: CGPoint(x: 310, y: 50))
        guard let movedWaypoint = view.connectorViewGeometry(connector)?.waypoint else {
            return XCTFail("Expected resolvable geometry after moving target")
        }
        XCTAssertEqual(movedWaypoint.x, 240, accuracy: 0.01, "Re-clamped outside the new target rect")
        XCTAssertEqual(movedWaypoint.y, 50, accuracy: 0.01)
        XCTAssertEqual(connector.waypointOffsetX, 90, "Draw-time re-clamp must not rewrite the stored offset")
        XCTAssertEqual(connector.waypointOffsetY, 0)

        // Moving the target back restores the un-clamped position exactly (pure function, no drift).
        pushScene(connector: connector, sourceCenter: CGPoint(x: 50, y: 50), targetCenter: CGPoint(x: 350, y: 50))
        guard let restoredWaypoint = view.connectorViewGeometry(connector)?.waypoint else {
            return XCTFail("Expected resolvable geometry after restoring target")
        }
        XCTAssertEqual(restoredWaypoint.x, initialWaypoint.x, accuracy: 0.01)
        XCTAssertEqual(restoredWaypoint.y, initialWaypoint.y, accuracy: 0.01)
    }

    // MARK: - Helpers

    private func makeConnector(offsetX: Double?, offsetY: Double?) -> ConnectorResponse {
        ConnectorResponse(
            id: connectorID, sourceStickyID: sourceID, sourceEdge: .right,
            targetStickyID: targetID, targetEdge: .left,
            cap: .arrow, routing: .elbow, strokeColorHex: nil,
            strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
            waypointOffsetX: offsetX, waypointOffsetY: offsetY
        )
    }

    private func pushScene(connector: ConnectorResponse, sourceCenter: CGPoint, targetCenter: CGPoint,
                           size: CGSize = CGSize(width: 100, height: 80)) {
        let source = stickyFixture(id: sourceID, centerX: sourceCenter.x, centerY: sourceCenter.y,
                                   width: size.width, height: size.height)
        let target = stickyFixture(id: targetID, centerX: targetCenter.x, centerY: targetCenter.y,
                                   width: size.width, height: size.height)
        view.update(
            CanvasContent(stickies: [source, target], shapes: [], images: [], texts: [],
                          connectors: [connector]),
            selectedIDs: [connector.id], settings: nil, global: nil
        )
    }
}

// MARK: - Fixtures

private func stickyFixture(id: UUID, centerX: Double, centerY: Double,
                           width: Double = 100, height: Double = 80) -> StickyResponse {
    StickyResponse(
        id: id, content: "", isTask: false, linkedCardTitle: nil,
        positionX: centerX, positionY: centerY, width: width, height: height,
        minWidth: 40, minHeight: 40, maxWidth: 400, maxHeight: 400,
        textColorHex: "000000", fontSize: 13, fillColorHex: nil, sortIndex: 0, labels: []
    )
}

// MARK: - Spy action handler
//
// Captures the waypoint edits `commitConnectorWaypoint` emits; every other action is a no-op. Mirrors
// `CanvasNSViewConnectorReconnectTests`'s spy (same per-file convention — no shared fake in
// `Tests/Support/` for `CanvasActionHandler`).

@MainActor
private final class SpyCanvasActionHandler: CanvasActionHandler {

    private(set) var waypointEdits: [(id: UUID, offsetX: Double, offsetY: Double)] = []

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
    func reconnectConnector(_ gesture: ConnectorReconnectGesture) {}
    func selectConnector(id: UUID?) {}
    func deleteConnector(id: UUID) {}
}
