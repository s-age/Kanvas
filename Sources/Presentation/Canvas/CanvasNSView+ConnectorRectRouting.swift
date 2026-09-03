import AppKit

// MARK: - Rectangle-aware elbow routing (ticket 805F3652 Phase 2 §B/§C)
//
// Given the endpoint stickies' real rects (not just their edge midpoints), route an elbow connector
// so it never crosses either rect's interior — automatic route (§B) and a waypointed route's two legs
// (§C) share the same strategy and primitives: try the direct Phase 1 shape first (cheap, preserves
// every Phase 1 test in the common safe case); if it crosses, bridge the two ends via a small fixed
// set of candidate detours and take the shortest one that verifies safe; if none is safe (only
// reachable when the two rects themselves overlap — an out-of-scope layout, ticket 805F3652 Phase 2
// §B "既知の限界"), fall back to the direct shape and accept the crossing rather than draw nothing.
// This file is a direct Swift port of the design's Python reference (`phase2_router.py`,
// `phase2_waypoint.py`'s `safe_leg`) — verified there across a 200k-case random sweep (0 crossings in
// non-overlapping layouts); see the card for the numbers. `clipLeavingOffset`'s two direction branches
// drop two of the reference's guard conditions each (an "already past the rect" check and a "the full
// unclipped ray would reach the rect" check): both are provably implied by the final `entry > 0` test
// that follows them (a negative or already-satisfied `entry` fails that test either way), so dropping
// them changes nothing observable — it only exists here to fit the file's complexity budget.

/// Fixed clearance (view points) a detour keeps outside the endpoint rects' union bbox. Shared by the
/// bridge-candidate generator and the waypoint clamp (`+ConnectorWaypoint.swift`) so the two can't
/// drift (review-checklist item 3).
let connectorRectMargin: CGFloat = 20

/// The two endpoint stickies' rects, bundled so the routing functions below stay within the
/// parameter-count budget (mirrors `ConnectorViewGeometry`'s own reason for bundling).
struct ConnectorEndpointRects {
    let source: CGRect
    let target: CGRect
}

extension CanvasNSView {

    // MARK: Segment/rect crossing

    /// Whether the axis-aligned segment `p1`–`p2` crosses `rect`'s *interior* (a segment that only
    /// touches a boundary — the common case for a leg leaving its own sticky's edge — does not count,
    /// so a route's own first/last segment is never a false positive). `p1`–`p2` is assumed
    /// horizontal or vertical, true for every segment an elbow route ever produces. Eps-tolerant at
    /// both the verticality test and the boundary comparisons, matching the design's reference
    /// implementation exactly (`1e-9` / `1e-6`) so the "0 crossings" sweep result carries over.
    func segmentCrossesRectInterior(_ p1: CGPoint, _ p2: CGPoint, rect: CGRect, eps: CGFloat = 1e-6) -> Bool {
        if abs(p1.x - p2.x) < 1e-9 {
            let x = p1.x
            guard rect.minX + eps < x, x < rect.maxX - eps else { return false }
            let y0 = min(p1.y, p2.y), y1 = max(p1.y, p2.y)
            return !(y1 <= rect.minY + eps || y0 >= rect.maxY - eps)
        }
        let y = p1.y
        guard rect.minY + eps < y, y < rect.maxY - eps else { return false }
        let x0 = min(p1.x, p2.x), x1 = max(p1.x, p2.x)
        return !(x1 <= rect.minX + eps || x0 >= rect.maxX - eps)
    }

    /// Whether any consecutive segment of `points` crosses any rect in `rects`.
    func routeCrossesRects(_ points: [CGPoint], rects: [CGRect]) -> Bool {
        guard points.count >= 2 else { return false }
        for i in 0..<(points.count - 1) {
            for rect in rects where segmentCrossesRectInterior(points[i], points[i + 1], rect: rect) {
                return true
            }
        }
        return false
    }

    private func pathLength(_ points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else { return 0 }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            total += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        return total
    }

    // MARK: Candidate detours

    /// Up to 8 candidate routes bridging `from` to `to` via a corridor kept outside the two rects'
    /// union bbox (plus `margin`): both pivot orderings (change y first then x, or x first then y)
    /// crossed with both near/far sides on each axis. The combination order below (outer `byY`, inner
    /// `bxX`, V-then-H-then-V before H-then-V-then-H) is load-bearing for the tie-break in
    /// `safeAutoRoute`/`safeElbowLeg` (`min(by:)` keeps the FIRST minimum, same as the design's
    /// Python `min` on this exact generation order) — do not reorder without re-verifying the sweep.
    private func bridgeCandidates(from sPrime: CGPoint, to ePrime: CGPoint,
                                  rects: ConnectorEndpointRects, margin: CGFloat) -> [[CGPoint]] {
        let unionMinX = min(rects.source.minX, rects.target.minX)
        let unionMaxX = max(rects.source.maxX, rects.target.maxX)
        let unionMinY = min(rects.source.minY, rects.target.minY)
        let unionMaxY = max(rects.source.maxY, rects.target.maxY)
        var candidates: [[CGPoint]] = []
        for byY in [unionMinY - margin, unionMaxY + margin] {
            for bxX in [unionMinX - margin, unionMaxX + margin] {
                candidates.append(dedupedPolyline([
                    sPrime, CGPoint(x: sPrime.x, y: byY), CGPoint(x: bxX, y: byY),
                    CGPoint(x: bxX, y: ePrime.y), ePrime,
                ]))
                candidates.append(dedupedPolyline([
                    sPrime, CGPoint(x: bxX, y: sPrime.y), CGPoint(x: bxX, y: byY),
                    CGPoint(x: ePrime.x, y: byY), ePrime,
                ]))
            }
        }
        return candidates
    }

    /// If the straight perpendicular exit from `start` along `n1` by `offset` would enter
    /// `otherRect`'s interior, clip `offset` down to just short of entry so the exit segment itself
    /// never crosses; unchanged if `start`'s band on the ray's fixed axis lies entirely outside
    /// `otherRect` (the ray can never enter) or the clip distance isn't positive. Dispatches to the
    /// horizontal- or vertical-ray kernel below (each within the file's complexity/parameter budget on
    /// its own; a merged single-function version isn't).
    private func clipLeavingOffset(from start: CGPoint, normal n1: CGVector, offset: CGFloat,
                                   otherRect: CGRect) -> CGFloat {
        n1.dx != 0
            ? clipLeavingOffsetHorizontal(from: start, direction: n1.dx, offset: offset, otherRect: otherRect)
            : clipLeavingOffsetVertical(from: start, direction: n1.dy, offset: offset, otherRect: otherRect)
    }

    /// `clipLeavingOffset`'s kernel for a horizontal ray (`n1.dx != 0`): `direction` is `n1.dx` (±1).
    private func clipLeavingOffsetHorizontal(from start: CGPoint, direction: CGFloat, offset: CGFloat,
                                             otherRect: CGRect) -> CGFloat {
        guard otherRect.minY < start.y, start.y < otherRect.maxY else { return offset }
        let entry = direction > 0 ? otherRect.minX - start.x : start.x - otherRect.maxX
        return entry > 0 ? min(offset, entry) : offset
    }

    /// `clipLeavingOffset`'s kernel for a vertical ray (`n1.dx == 0`): `direction` is `n1.dy` (±1).
    private func clipLeavingOffsetVertical(from start: CGPoint, direction: CGFloat, offset: CGFloat,
                                           otherRect: CGRect) -> CGFloat {
        guard otherRect.minX < start.x, start.x < otherRect.maxX else { return offset }
        let entry = direction > 0 ? otherRect.minY - start.y : start.y - otherRect.maxY
        return entry > 0 ? min(offset, entry) : offset
    }

    // MARK: §B — automatic route

    /// The rect-aware automatic elbow route: `direct` (the already-computed Phase 1 route) as-is if
    /// it crosses neither of `geo`'s endpoint rects; otherwise clip each endpoint's step-out against
    /// the OTHER rect (`clipLeavingOffset`) and bridge the clipped points via `bridgeCandidates`,
    /// taking the shortest safe one; if none is safe, fall back to `direct` (crossing accepted — no
    /// other route to draw, only reachable when the two rects overlap, ticket 805F3652 Phase 2 §B).
    /// `nil` rects (a `straight` connector, or an endpoint sticky that failed to resolve) skip all of
    /// this and return `direct` unchanged.
    func safeAutoRoute(direct: [CGPoint], in geo: ConnectorViewGeometry, offset: CGFloat) -> [CGPoint] {
        guard let sourceRect = geo.sourceRect, let targetRect = geo.targetRect else { return direct }
        let rects = [sourceRect, targetRect]
        guard routeCrossesRects(direct, rects: rects) else { return direct }
        let n1 = outwardNormal(geo.sourceEdge)
        let n2 = outwardNormal(geo.targetEdge)
        let clippedSourceOffset = clipLeavingOffset(from: geo.start, normal: n1, offset: offset, otherRect: targetRect)
        let clippedTargetOffset = clipLeavingOffset(from: geo.end, normal: n2, offset: offset, otherRect: sourceRect)
        let sPrime = CGPoint(x: geo.start.x + n1.dx * clippedSourceOffset, y: geo.start.y + n1.dy * clippedSourceOffset)
        let ePrime = CGPoint(x: geo.end.x + n2.dx * clippedTargetOffset, y: geo.end.y + n2.dy * clippedTargetOffset)
        let candidates = bridgeCandidates(from: sPrime, to: ePrime,
                                          rects: ConnectorEndpointRects(source: sourceRect, target: targetRect),
                                          margin: connectorRectMargin)
            .map { dedupedPolyline([geo.start] + $0 + [geo.end]) }
            .filter { !routeCrossesRects($0, rects: rects) }
        return candidates.min { pathLength($0) < pathLength($1) } ?? direct
    }

    // MARK: §C — waypoint leg

    /// The rect-aware version of one waypointed elbow leg: `direct` (the leg's exact Phase 1 shape,
    /// `[from, ...corners, to]`, already built by the caller) as-is if it crosses neither of `geo`'s
    /// endpoint rects; otherwise bridge `from` to `to` directly via `bridgeCandidates` (no separate
    /// step-out — a leg has none, unlike the auto route's `sPrime`/`ePrime`) and take the shortest
    /// safe candidate; if none is safe, fall back to `direct` (same rationale as `safeAutoRoute`'s
    /// fallback). `nil` rects return `direct` unchanged.
    func safeElbowLeg(direct: [CGPoint], from: CGPoint, to: CGPoint, in geo: ConnectorViewGeometry) -> [CGPoint] {
        guard let sourceRect = geo.sourceRect, let targetRect = geo.targetRect else { return direct }
        let rects = [sourceRect, targetRect]
        guard routeCrossesRects(direct, rects: rects) else { return direct }
        let candidates = bridgeCandidates(from: from, to: to,
                                          rects: ConnectorEndpointRects(source: sourceRect, target: targetRect),
                                          margin: connectorRectMargin)
            .filter { !routeCrossesRects($0, rects: rects) }
        return candidates.min { pathLength($0) < pathLength($1) } ?? direct
    }
}
