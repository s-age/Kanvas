import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the *automatic* (no-waypoint) elbow connector route (ticket
/// AF4CE767). The old auto-elbow bent only to the endpoints' midline, so a route whose endpoints
/// shared an axis (e.g. two stickies at the same level connected top→top) collapsed to a flat line —
/// the bracket had zero height. The fix steps out of *both* edges along their outward normals by the
/// same `max(40, dist × 0.4)` offset `curve(_:)` uses, so the route always brackets out by that
/// height. These tests pin (a) the guaranteed bracket height in the reported same-level case,
/// (b) that the source/target edges are both honoured, and (c) that the elbow's step-out offset
/// stays in lock-step with the curve's (the shared `connectorNormalOffset`).
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity: world and
/// view coordinates coincide, keeping the asserted points easy to reason about.
@MainActor
final class CanvasNSViewElbowAutoRouteTests: XCTestCase {

    private var view: CanvasNSView!
    private let sourceID = UUID()
    private let targetID = UUID()
    private let connectorID = UUID()

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
    }

    override func tearDown() {
        view = nil
        super.tearDown()
    }

    // MARK: - reported case: top→top at the same level brackets out by the offset height

    func testElbowAuto_topToTopSameLevel_bracketsOutByOffsetHeight() {
        // Both stickies at y == 0; top edges face up. Source top-mid (-100, -40), target top-mid
        // (100, -40) share a y, so the old midline route was flat. The fixed route must rise above
        // both endpoints by the step-out offset (= max(40, dist*0.4)).
        let connector = makeConnector(sourceEdge: .top, targetEdge: .top)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 0))

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let offset = view.connectorNormalOffset(start: geo.start, end: geo.end)
        let pts = view.elbowPoints(geo)
        // Top edge points up (negative y); the route's highest excursion is `offset` above the
        // endpoints, so the minimum y equals start.y - offset.
        let minY = pts.map(\.y).min() ?? .nan

        XCTAssertEqual(minY, geo.start.y - offset, accuracy: 0.001,
                       "Same-level top→top route must bracket up by the full step-out offset")
    }

    func testElbowAuto_topToTopSameLevel_isNotFlat() {
        // Direct regression for the bug: the route must span a non-zero vertical range.
        let connector = makeConnector(sourceEdge: .top, targetEdge: .top)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 0))

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)
        let span = (pts.map(\.y).max() ?? 0) - (pts.map(\.y).min() ?? 0)

        XCTAssertGreaterThan(span, 1, "Same-level elbow route must not collapse to a flat line")
    }

    func testElbowAuto_topToTopSameLevel_hasNoZeroLengthSegment() {
        // The degenerate same-level case yields corner == ePrime; the dedup must remove it so every
        // drawn segment has length (and the arrowhead tangent pts[count-2] is well-defined).
        let connector = makeConnector(sourceEdge: .top, targetEdge: .top)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 0))

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)
        let hasZeroSegment = (0..<(pts.count - 1)).contains { i in
            abs(pts[i].x - pts[i + 1].x) < 0.001 && abs(pts[i].y - pts[i + 1].y) < 0.001
        }

        XCTAssertFalse(hasZeroSegment, "Deduped route must contain no zero-length segment")
    }

    // MARK: - both edges honoured (target edge no longer ignored)

    func testElbowAuto_topToLeft_arrivesHorizontallyIntoLeftEdge() {
        // Source top edge (steps up), target left edge (must dock horizontally). The last segment
        // into the target must be horizontal — proving the target edge is respected, not just the
        // source. The pre-fix midline route ignored the target edge entirely.
        let connector = makeConnector(sourceEdge: .top, targetEdge: .left)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 200))

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)
        let last = pts[pts.count - 1]
        let penultimate = pts[pts.count - 2]

        XCTAssertEqual(penultimate.y, last.y, accuracy: 0.001,
                       "Last segment into a .left target must be horizontal (perpendicular docking)")
        XCTAssertNotEqual(penultimate.x, last.x, accuracy: 0.001,
                          "Last segment must actually move into the edge, not be degenerate")
    }

    func testElbowAuto_topSource_leavesVerticallyFromSourceEdge() {
        // The first segment out of a top-edge source must be vertical (perpendicular to the edge).
        let connector = makeConnector(sourceEdge: .top, targetEdge: .left)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 200))

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)

        XCTAssertEqual(pts[0].x, pts[1].x, accuracy: 0.001,
                       "First segment out of a .top source must be vertical (perpendicular exit)")
        XCTAssertNotEqual(pts[0].y, pts[1].y, accuracy: 0.001,
                          "First segment must actually leave the edge")
    }

    // MARK: - auto-elbow deformation handle sits at the route's geometric centre (ticket AF4CE767)

    func testElbowAuto_handle_sitsAtArcLengthMidpointOfRoute() {
        // The auto route is [start, sPrime, corner, ePrime, end]; sPrime/corner cluster near the
        // source, so a fixed interior-vertex midpoint (the old pts[1]/pts[2] mean) biased the handle
        // toward the source. The handle must instead seat at the route's arc-length midpoint.
        let connector = makeConnector(sourceEdge: .top, targetEdge: .left)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 200))

        guard let geo = view.connectorViewGeometry(connector),
              let handle = view.connectorWaypointHandleView(connector) else {
            return XCTFail("Expected resolvable elbow geometry + handle")
        }
        let expected = view.polylineMidpoint(view.elbowPoints(geo))

        XCTAssertEqual(handle.x, expected.x, accuracy: 0.001,
                       "Auto-elbow handle x must match the route's arc-length midpoint")
        XCTAssertEqual(handle.y, expected.y, accuracy: 0.001,
                       "Auto-elbow handle y must match the route's arc-length midpoint")
    }

    func testElbowAuto_handle_isOnTheDrawnRoute() {
        // Whatever centre we choose, the handle must actually lie on the polyline the user sees, so
        // "grab the middle to bend it" grabs a point on the line.
        let connector = makeConnector(sourceEdge: .top, targetEdge: .left)
        pushScene(connector: connector, sourceCenter: CGPoint(x: -100, y: 0),
                  targetCenter: CGPoint(x: 100, y: 200))

        guard let geo = view.connectorViewGeometry(connector),
              let handle = view.connectorWaypointHandleView(connector) else {
            return XCTFail("Expected resolvable elbow geometry + handle")
        }
        let distanceToRoute = view.distance(from: handle, toPolyline: view.elbowPoints(geo))

        XCTAssertLessThan(distanceToRoute, 0.001, "Auto-elbow handle must lie on the drawn route")
    }

    func testPolylineMidpoint_splitsTotalArcLengthInHalf() {
        // An L-shaped polyline: a 100-unit horizontal leg then a 100-unit vertical leg (total 200).
        // The arc-length midpoint at 100 sits exactly on the corner.
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0), CGPoint(x: 100, y: 100)]

        let mid = view.polylineMidpoint(points)

        XCTAssertEqual(mid.x, 100, accuracy: 0.001)
        XCTAssertEqual(mid.y, 0, accuracy: 0.001)
    }

    // MARK: - step-out offset is shared with the curve router

    func testElbowAuto_normalOffsetMatchesCurveFormula() {
        // The extracted `connectorNormalOffset` must equal the `max(40, dist*0.4)` the curve uses, so
        // the two routers can't drift. Pick a distance where dist*0.4 dominates the 40 floor.
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 300, y: 400)   // dist 500 ⇒ 0.4*500 = 200 > 40
        let expected = max(40, hypot(end.x - start.x, end.y - start.y) * 0.4)

        XCTAssertEqual(view.connectorNormalOffset(start: start, end: end), expected, accuracy: 0.001)
    }

    func testElbowAuto_normalOffset_floorsAt40() {
        // For nearby endpoints the offset must clamp up to the 40 floor.
        let start = CGPoint(x: 0, y: 0)
        let end = CGPoint(x: 10, y: 0)      // dist 10 ⇒ 0.4*10 = 4 < 40

        XCTAssertEqual(view.connectorNormalOffset(start: start, end: end), 40, accuracy: 0.001)
    }

    // MARK: - Helpers

    private func makeConnector(sourceEdge: CanvasEdgeResponse, targetEdge: CanvasEdgeResponse)
        -> ConnectorResponse {
        ConnectorResponse(
            id: connectorID, sourceStickyID: sourceID, sourceEdge: sourceEdge,
            targetStickyID: targetID, targetEdge: targetEdge,
            cap: .arrow, routing: .elbow, strokeColorHex: nil,
            strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
            waypointOffsetX: nil, waypointOffsetY: nil
        )
    }

    private func pushScene(connector: ConnectorResponse, sourceCenter: CGPoint, targetCenter: CGPoint) {
        let source = stickyFixture(id: sourceID, centerX: sourceCenter.x, centerY: sourceCenter.y)
        let target = stickyFixture(id: targetID, centerX: targetCenter.x, centerY: targetCenter.y)
        view.update(
            CanvasContent(stickies: [source, target], shapes: [], images: [], texts: [],
                          connectors: [connector]),
            selectedIDs: [connector.id], settings: nil, global: nil
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
