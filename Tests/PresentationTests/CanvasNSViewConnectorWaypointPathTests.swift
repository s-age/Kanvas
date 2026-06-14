import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the connector *waypoint* deformation geometry (ticket D43B0596,
/// review finding r1-1): the rendered route must actually pass through the waypoint the handle is
/// drawn on. The original curve pulled each control point only halfway toward the waypoint, so the
/// cubic's t=0.5 point lagged the handle (~37px adrift in the worked example below); the handle
/// floated off the line it marked. These tests pin the contract that
/// `connectorWaypointHandleView(_:)` (the handle position) and the rendered path (curve at t=0.5 /
/// elbow corner) coincide.
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity here: world
/// and view coordinates coincide, keeping the asserted points easy to reason about.
@MainActor
final class CanvasNSViewConnectorWaypointPathTests: XCTestCase {

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

    // MARK: - curve passes through the waypoint at t=0.5 (r1-1)

    func testCurveWaypoint_curvePointAtMidpoint_equalsHandlePosition() {
        // Source right-edge midpoint at (-150, 0), target left-edge midpoint at (150, 0). A waypoint
        // offset of (0, 60) puts the handle 60 below the route midpoint (0, 0) → world (0, 60).
        let connector = makeConnector(routing: .curve, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector),
              let handle = view.connectorWaypointHandleView(connector) else {
            return XCTFail("Expected resolvable curve geometry + handle")
        }
        let curvePoint = view.cubicPoint(view.curve(geo), at: 0.5)

        // The rendered curve at its midpoint must sit on the handle, not adrift from it.
        XCTAssertEqual(curvePoint.x, handle.x, accuracy: 0.001)
        XCTAssertEqual(curvePoint.y, handle.y, accuracy: 0.001)
    }

    func testCurveWaypoint_handleSitsOnTheWaypoint() {
        // The handle for a waypointed connector is the waypoint itself (world (0, 60) here).
        let connector = makeConnector(routing: .curve, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        let handle = view.connectorWaypointHandleView(connector)

        XCTAssertEqual(handle?.x ?? .nan, 0, accuracy: 0.001)
        XCTAssertEqual(handle?.y ?? .nan, 60, accuracy: 0.001)
    }

    // MARK: - elbow already routed through the waypoint (unchanged by r1-1)

    func testElbowWaypoint_routePassesThroughHandle() {
        let connector = makeConnector(routing: .elbow, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector),
              let handle = view.connectorWaypointHandleView(connector) else {
            return XCTFail("Expected resolvable elbow geometry + handle")
        }
        // The waypoint vertex is one of the elbow polyline's points.
        let onRoute = view.elbowPoints(geo).contains {
            abs($0.x - handle.x) < 0.001 && abs($0.y - handle.y) < 0.001
        }

        XCTAssertTrue(onRoute, "Elbow route must include the waypoint vertex the handle marks")
    }

    func testElbowWaypoint_lastSegmentArrivesPerpendicularToTargetEdge() {
        // The deformed route must DOCK into the target the same way the un-deformed elbow does: a
        // `.left` target is entered horizontally (last segment horizontal, along the edge's outward
        // normal), not parallel to / grazing the edge. This pins review finding r2-1 — the arriving
        // leg previously reused the source-side "leave perpendicular" rule, making the last segment
        // vertical (running ALONG the left edge).
        let connector = makeConnector(routing: .elbow, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)
        let last = pts[pts.count - 1]
        let penultimate = pts[pts.count - 2]

        // Last segment horizontal ⇒ shares y with the endpoint (perpendicular to the .left edge).
        XCTAssertEqual(penultimate.y, last.y, accuracy: 0.001,
                       "Last segment into a .left target must be horizontal (perpendicular docking)")
        XCTAssertNotEqual(penultimate.x, last.x, accuracy: 0.001,
                          "Last segment must actually move into the edge, not be degenerate")
    }

    func testElbowWaypoint_horizontalRunWithVerticalOffset_doesNotSelfOverlap() {
        // Review finding r3-1: a left/right-edge connector whose endpoints share a y (a horizontal
        // run) dragged up/down used to spike — both leg corners collapsed onto (waypoint.x, endpointY)
        // so the route climbed to the waypoint along x=waypoint.x and immediately retraced the SAME
        // vertical back down before continuing. The route must instead straddle the waypoint so no
        // segment is retraced. Endpoints (-150,0)/(150,0), waypoint (0,60).
        let connector = makeConnector(routing: .elbow, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)

        // No two consecutive segments may be exact opposites (anti-parallel) — that is a back-track.
        for i in 0..<(pts.count - 2) {
            let a = CGVector(dx: pts[i + 1].x - pts[i].x, dy: pts[i + 1].y - pts[i].y)
            let b = CGVector(dx: pts[i + 2].x - pts[i + 1].x, dy: pts[i + 2].y - pts[i + 1].y)
            let antiParallel = abs(a.dx + b.dx) < 0.001 && abs(a.dy + b.dy) < 0.001
                && (abs(a.dx) > 0.001 || abs(a.dy) > 0.001)
            XCTAssertFalse(antiParallel,
                           "Segments \(i)->\(i + 1) and \(i + 1)->\(i + 2) retrace each other")
        }
    }

    func testElbowWaypoint_horizontalRunWithVerticalOffset_hasNoRepeatedInteriorVertex() {
        // Companion to the anti-parallel check: the degenerate spike also produced a repeated interior
        // vertex (both corners at (waypoint.x, endpointY)). A clean route visits each vertex once.
        let connector = makeConnector(routing: .elbow, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)
        let hasDuplicate = (0..<pts.count).contains { i in
            ((i + 1)..<pts.count).contains { j in
                abs(pts[i].x - pts[j].x) < 0.001 && abs(pts[i].y - pts[j].y) < 0.001
            }
        }

        XCTAssertFalse(hasDuplicate, "Elbow route must not revisit any vertex (no spike back-track)")
    }

    func testElbowWaypoint_asymmetricOffset_doesNotSelfOverlap() {
        // The spike held for asymmetric offsets too (e.g. (40,60)); pin that this no longer back-tracks.
        let connector = makeConnector(routing: .elbow, offsetX: 40, offsetY: 60)
        pushScene(connector: connector)

        guard let geo = view.connectorViewGeometry(connector) else {
            return XCTFail("Expected resolvable elbow geometry")
        }
        let pts = view.elbowPoints(geo)

        for i in 0..<(pts.count - 2) {
            let a = CGVector(dx: pts[i + 1].x - pts[i].x, dy: pts[i + 1].y - pts[i].y)
            let b = CGVector(dx: pts[i + 2].x - pts[i + 1].x, dy: pts[i + 2].y - pts[i + 1].y)
            let antiParallel = abs(a.dx + b.dx) < 0.001 && abs(a.dy + b.dy) < 0.001
                && (abs(a.dx) > 0.001 || abs(a.dy) > 0.001)
            XCTAssertFalse(antiParallel,
                           "Asymmetric-offset route segments \(i) and \(i + 1) retrace each other")
        }
    }

    // MARK: - straight connectors carry no waypoint handle

    func testStraightConnector_hasNoWaypointHandle() {
        let connector = makeConnector(routing: .straight, offsetX: 0, offsetY: 60)
        pushScene(connector: connector)

        XCTAssertNil(view.connectorWaypointHandleView(connector))
    }

    // MARK: - Helpers

    private func makeConnector(routing: ConnectorRoutingResponse, offsetX: Double, offsetY: Double)
        -> ConnectorResponse {
        ConnectorResponse(
            id: connectorID, sourceStickyID: sourceID, sourceEdge: .right,
            targetStickyID: targetID, targetEdge: .left,
            cap: .arrow, routing: routing, strokeColorHex: nil,
            strokeWidth: 2, minStrokeWidth: 1, maxStrokeWidth: 40,
            waypointOffsetX: offsetX, waypointOffsetY: offsetY
        )
    }

    /// Source sticky centred at (-200, 0) (right-edge midpoint (-150, 0)), target at (200, 0)
    /// (left-edge midpoint (150, 0)); the route midpoint is the world origin.
    private func pushScene(connector: ConnectorResponse) {
        let source = stickyFixture(id: sourceID, centerX: -200, centerY: 0)
        let target = stickyFixture(id: targetID, centerX: 200, centerY: 0)
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
