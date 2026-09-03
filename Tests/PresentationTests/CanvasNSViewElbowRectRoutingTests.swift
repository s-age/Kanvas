import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for the Phase 2 rectangle-aware automatic elbow route (ticket 805F3652
/// §B / D-4): with real endpoint rects available (not just edge midpoints), `elbowPoints` must never
/// draw a route that crosses either sticky's interior, falling back to a bridge-candidate detour only
/// when the Phase 1 direct route would cross, and to the Phase 1 route (crossing accepted) only when
/// no detour candidate is safe — reachable solely when the two rects themselves overlap, an
/// out-of-scope layout the fallback must survive without crashing.
///
/// Fixtures below (source/target centre, size, edge) were found by running this file's Swift logic's
/// Python reference implementation (`phase2_router.py`, `phase2_explore2.py` — see the card) over a
/// 200k-case random sweep and rounding one hit per category to 1 decimal place, then re-verifying the
/// rounded inputs still cross pre-fix and clear post-fix. Expected detour coordinates are copied
/// verbatim from that re-verification run, so a port bug that produces a different-but-still-safe
/// route is still caught (not just "did it cross").
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `worldToView` is the identity: geometry is
/// built directly (no sticky/`CanvasContent` plumbing needed) and its `start`/`end`/rects are already
/// in view space.
@MainActor
final class CanvasNSViewElbowRectRoutingTests: XCTestCase {

    private var view: CanvasNSView!

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
    }

    override func tearDown() {
        view = nil
        super.tearDown()
    }

    // MARK: - D-4: one representative fixture per Phase 1 branch, each requiring a detour

    func testCrossAxis_detourAvoidsBothRectsAndMatchesReferenceRoute() {
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: -179.6, y: -299.6), size: CGSize(width: 116.2, height: 104.2),
                                 edge: .bottom),
            target: EndpointSpec(center: CGPoint(x: 347.5, y: -36.0), size: CGSize(width: 137.0, height: 126.5),
                                 edge: .right)
        )
        let expected = [
            CGPoint(x: -179.6, y: -247.5), CGPoint(x: -179.6, y: 5.315066006755245),
            CGPoint(x: -179.6, y: 47.25), CGPoint(x: 436.0, y: 47.25), CGPoint(x: 436.0, y: -36.0),
            CGPoint(x: 668.8150660067553, y: -36.0), CGPoint(x: 416.0, y: -36.0),
        ]
        assertDetour(geo, expectedRoute: expected)
    }

    func testOppositeSignFold_detourAvoidsBothRectsAndMatchesReferenceRoute() {
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: -176.3, y: 50.9), size: CGSize(width: 94.6, height: 129.6),
                                 edge: .left),
            target: EndpointSpec(center: CGPoint(x: -19.3, y: -167.9), size: CGSize(width: 73.9, height: 75.4),
                                 edge: .right)
        )
        let expected = [
            CGPoint(x: -223.6, y: 50.9), CGPoint(x: -353.8766302910849, y: 50.9),
            CGPoint(x: -243.6, y: 50.9), CGPoint(x: -243.6, y: -225.6),
            CGPoint(x: 147.92663029108485, y: -225.6), CGPoint(x: 147.92663029108485, y: -167.9),
            CGPoint(x: 17.65, y: -167.9),
        ]
        assertDetour(geo, expectedRoute: expected)
    }

    func testSameSignFold_detourAvoidsBothRectsAndMatchesReferenceRoute() {
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: 52.2, y: 272.5), size: CGSize(width: 109.1, height: 135.4),
                                 edge: .left),
            target: EndpointSpec(center: CGPoint(x: -208.5, y: 301.3), size: CGSize(width: 102.1, height: 126.6),
                                 edge: .left)
        )
        let expected = [
            CGPoint(x: -2.35, y: 272.5), CGPoint(x: -105.87296749997077, y: 272.5),
            CGPoint(x: -105.87296749997077, y: 384.6), CGPoint(x: -279.55, y: 384.6),
            CGPoint(x: -279.55, y: 301.3), CGPoint(x: -363.0729674999708, y: 301.3), CGPoint(x: -259.55, y: 301.3),
        ]
        assertDetour(geo, expectedRoute: expected)
    }

    func testNoCap_detourAvoidsBothRectsAndMatchesReferenceRoute() {
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: -302.0, y: 103.1), size: CGSize(width: 137.3, height: 71.7),
                                 edge: .left),
            target: EndpointSpec(center: CGPoint(x: -28.0, y: 75.4), size: CGSize(width: 61.0, height: 141.8),
                                 edge: .left)
        )
        let expected = [
            CGPoint(x: -370.65, y: 103.1), CGPoint(x: -496.00065217221646, y: 103.1),
            CGPoint(x: -390.65, y: 103.1), CGPoint(x: -390.65, y: 166.3),
            CGPoint(x: -183.85065217221648, y: 166.3), CGPoint(x: -183.85065217221648, y: 75.4),
            CGPoint(x: -58.5, y: 75.4),
        ]
        assertDetour(geo, expectedRoute: expected)
    }

    /// Asserts `geo`'s Phase 1 route (rects stripped) crosses, its Phase 2 route doesn't, and the
    /// Phase 2 route matches `expectedRoute` (proving the specific detour shape, not just safety).
    private func assertDetour(_ geo: ConnectorViewGeometry, expectedRoute: [CGPoint],
                              file: StaticString = #filePath, line: UInt = #line) {
        var bare = geo
        bare.sourceRect = nil
        bare.targetRect = nil
        let phase1Route = view.elbowPoints(bare)
        XCTAssertTrue(view.routeCrossesRects(phase1Route, rects: [geo.sourceRect!, geo.targetRect!]),
                      "Fixture must actually need a detour (Phase 1 route crosses a rect)", file: file, line: line)

        let route = view.elbowPoints(geo)
        XCTAssertFalse(view.routeCrossesRects(route, rects: [geo.sourceRect!, geo.targetRect!]),
                       "Phase 2 route must not cross either endpoint rect", file: file, line: line)
        XCTAssertEqual(route.count, expectedRoute.count, "Unexpected detour shape", file: file, line: line)
        for (p, e) in zip(route, expectedRoute) {
            XCTAssertEqual(p.x, e.x, accuracy: 0.05, file: file, line: line)
            XCTAssertEqual(p.y, e.y, accuracy: 0.05, file: file, line: line)
        }
    }

    // MARK: - D-4: overlapping rects fall back to the Phase 1 route without crashing

    func testOverlappingRects_noSafeCandidate_fallsBackToPhase1RouteWithoutCrashing() {
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: 29.1, y: 67.5), size: CGSize(width: 74.9, height: 157.5),
                                 edge: .top),
            target: EndpointSpec(center: CGPoint(x: 40.4, y: -49.3), size: CGSize(width: 148.1, height: 158.6),
                                 edge: .bottom)
        )
        XCTAssertTrue(rectsOverlap(geo.sourceRect!, geo.targetRect!), "Fixture must actually overlap")

        var bare = geo
        bare.sourceRect = nil
        bare.targetRect = nil
        let phase1Route = view.elbowPoints(bare)
        XCTAssertTrue(view.routeCrossesRects(phase1Route, rects: [geo.sourceRect!, geo.targetRect!]),
                      "Fixture's Phase 1 route must cross (so the fallback is actually exercised)")

        let route = view.elbowPoints(geo)  // must not crash
        XCTAssertEqual(route.count, phase1Route.count)
        for (p, e) in zip(route, phase1Route) {
            XCTAssertEqual(p.x, e.x, accuracy: 0.001)
            XCTAssertEqual(p.y, e.y, accuracy: 0.001)
        }
    }

    // MARK: - D-4 / D-6: a Phase 1 fixture that never needed a detour stays byte-identical

    func testAF4CE767Fixture_topToTopSameLevel_routeUnaffectedByRects() {
        // Same fixture as CanvasNSViewElbowAutoRouteTests' AF4CE767 case: two 100x80 stickies at the
        // same level, top->top. Real rects are wide enough apart that no detour should ever trigger.
        let geo = geometry(
            source: EndpointSpec(center: CGPoint(x: -100, y: 0), size: CGSize(width: 100, height: 80), edge: .top),
            target: EndpointSpec(center: CGPoint(x: 100, y: 0), size: CGSize(width: 100, height: 80), edge: .top)
        )
        var bare = geo
        bare.sourceRect = nil
        bare.targetRect = nil

        XCTAssertEqual(view.elbowPoints(geo), view.elbowPoints(bare),
                       "A route that never needed a detour must stay exactly the Phase 1 route")
    }

    // MARK: - D-4: small seeded random sweep over non-overlapping layouts

    func testRandomSweep_nonOverlappingLayouts_neverCrossesEitherRect() {
        var rng = SeededGenerator(seed: 0x9E3779B97F4A7C15)
        var checked = 0
        while checked < 300 {
            let sourceCenter = CGPoint(x: CGFloat.random(in: -400...400, using: &rng),
                                       y: CGFloat.random(in: -400...400, using: &rng))
            let sourceSize = CGSize(width: CGFloat.random(in: 60...160, using: &rng),
                                    height: CGFloat.random(in: 60...160, using: &rng))
            let sourceEdge = CanvasEdgeResponse.allCases.randomElement(using: &rng)!
            let targetCenter = CGPoint(x: CGFloat.random(in: -400...400, using: &rng),
                                       y: CGFloat.random(in: -400...400, using: &rng))
            let targetSize = CGSize(width: CGFloat.random(in: 60...160, using: &rng),
                                    height: CGFloat.random(in: 60...160, using: &rng))
            let targetEdge = CanvasEdgeResponse.allCases.randomElement(using: &rng)!
            let geo = geometry(source: EndpointSpec(center: sourceCenter, size: sourceSize, edge: sourceEdge),
                               target: EndpointSpec(center: targetCenter, size: targetSize, edge: targetEdge))
            guard !rectsOverlap(geo.sourceRect!, geo.targetRect!), geo.start != geo.end else { continue }
            checked += 1
            let route = view.elbowPoints(geo)
            XCTAssertFalse(view.routeCrossesRects(route, rects: [geo.sourceRect!, geo.targetRect!]),
                           "Iteration \(checked): route must not cross either rect (source=\(geo.sourceRect!), "
                           + "target=\(geo.targetRect!), se=\(sourceEdge), te=\(targetEdge))")
        }
    }

    // MARK: - Helpers

    private func geometry(source: EndpointSpec, target: EndpointSpec) -> ConnectorViewGeometry {
        let sourceRect = source.rect
        let targetRect = target.rect
        return ConnectorViewGeometry(
            start: view.edgeMidpoint(of: sourceRect, edge: source.edge),
            end: view.edgeMidpoint(of: targetRect, edge: target.edge),
            sourceEdge: source.edge, targetEdge: target.edge, waypoint: nil,
            sourceRect: sourceRect, targetRect: targetRect
        )
    }
}

/// A sticky's centre, size, and connecting edge — bundled so `geometry(source:target:)` stays within
/// the parameter-count budget.
private struct EndpointSpec {
    let center: CGPoint
    let size: CGSize
    let edge: CanvasEdgeResponse

    var rect: CGRect {
        CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height)
    }
}

/// A tiny deterministic xorshift64* generator so the random sweep above is 100% reproducible across
/// runs/machines (Swift's default `SystemRandomNumberGenerator` isn't seedable).
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state &* 0x2545F4914F6CDD1D
    }
}

private extension CanvasEdgeResponse {
    static var allCases: [CanvasEdgeResponse] { [.top, .bottom, .left, .right] }
}

/// Whether two axis-aligned rects overlap (share interior area) — a plain geometry check, not exposed
/// on `CanvasNSView` itself since only this test file's fixture selection needs it.
private func rectsOverlap(_ r1: CGRect, _ r2: CGRect) -> Bool {
    !(r1.maxX <= r2.minX || r2.maxX <= r1.minX || r1.maxY <= r2.minY || r2.maxY <= r1.minY)
}
