import AppKit

// MARK: - Trimmed stroke geometry for an arrow cap (ticket 805F3652)
//
// `drawConnector` (+Connectors.swift) trims the drawn line to the arrowhead's base when the
// connector's cap is `.arrow`. Trimming must touch only the path's tail: the waypoint handle
// position, the hit-test polyline, and the arrowhead's tangent all still key off the FULL untrimmed
// path (`connectorPath`/`elbowPoints`/`curve`). A naive rebuild that re-derives the whole route from
// a shortened endpoint (the pre-fix approach) shifts the full path's interior shape by several dozen
// points at large stroke widths — the card's measured deltas. `connectorStrokeGeometry` instead trims
// the already-built full geometry's tail in place, leaving its interior (control points / vertices)
// untouched, so the drawn line, the handle, the hit-test polyline, and the arrow tangent all still
// agree on the same underlying route.

/// Geometry actually stroked for a connector's line body. `arrowLength == nil` (cap == `.line`)
/// returns the full untrimmed path; a non-nil `arrowLength` trims only the tail, pulling the drawn
/// end back by that many view points so the stroke meets the arrowhead's base.
enum StrokeGeometry {
    case straight(CGPoint, CGPoint)
    case elbow([CGPoint])
    /// `sub` is the trimmed (left) De Casteljau subcurve; `tStar` is its split parameter on the full
    /// curve (`1` when untrimmed) — the parameter a test needs to relate `sub`'s points back to the
    /// full curve's.
    case curve(sub: CubicBezier, tStar: CGFloat)

    var path: NSBezierPath {
        let path = NSBezierPath()
        switch self {
        case let .straight(start, end):
            path.move(to: start)
            path.line(to: end)
        case let .elbow(points):
            if let first = points.first {
                path.move(to: first)
                for p in points.dropFirst() { path.line(to: p) }
            }
        case let .curve(sub, _):
            path.move(to: sub.start)
            path.curve(to: sub.end, controlPoint1: sub.c1, controlPoint2: sub.c2)
        }
        return path
    }
}

extension CanvasNSView {

    /// The trimmed-tail stroke geometry for `geo`/`routing`. `arrowLength: nil` returns the routing's
    /// full path unchanged (cap == `.line`); otherwise trims the tail by `arrowLength` view points,
    /// guarded (`min` against the trimmable length) so the trim never overshoots past the route's own
    /// interior geometry and folds the visible tail back on itself (frozen fact 2, ticket 805F3652).
    func connectorStrokeGeometry(_ geo: ConnectorViewGeometry, routing: ConnectorRoutingResponse,
                                  arrowLength: CGFloat?) -> StrokeGeometry {
        switch routing {
        case .straight:
            guard let arrowLength else { return .straight(geo.start, geo.end) }
            // No waypoint ever reaches a straight connector's geometry (`connectorViewGeometry`), so
            // there's no interior shape to protect here — matches the pre-fix trim byte-for-byte
            // (unguarded; straight routing is outside this card's scope).
            let direction = CGVector(dx: geo.end.x - geo.start.x, dy: geo.end.y - geo.start.y)
            let backEnd = pointBack(from: geo.end, along: direction, by: arrowLength)
            return .straight(geo.start, backEnd)
        case .elbow:
            let points = elbowPoints(geo)
            guard let arrowLength else { return .elbow(points) }
            return .elbow(trimmedElbowTail(points, by: arrowLength))
        case .curve:
            let bezier = curve(geo)
            guard let arrowLength else { return .curve(sub: bezier, tStar: 1) }
            let tStar = curveTrimParameter(bezier, chordLength: arrowLength)
            return .curve(sub: splitCubicBezier(bezier, at: tStar), tStar: tStar)
        }
    }

    /// `points` with its last vertex pulled back toward the penultimate one by
    /// `min(amount, lastSegmentLength)` — the clamp the card requires for both the automatic route's
    /// final leg and a waypointed route's arriving leg (which can be short), so a wide stroke's arrow
    /// length never overshoots the corner and folds the trimmed tail back on itself.
    private func trimmedElbowTail(_ points: [CGPoint], by amount: CGFloat) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        let last = points[points.count - 1]
        let prev = points[points.count - 2]
        let direction = CGVector(dx: last.x - prev.x, dy: last.y - prev.y)
        let segmentLength = hypot(direction.dx, direction.dy)
        var trimmed = points
        trimmed[trimmed.count - 1] = pointBack(from: last, along: direction, by: min(amount, segmentLength))
        return trimmed
    }

    /// Binary-searches the cubic Bézier parameter `t*` at which the chord distance from
    /// `cubicPoint(bezier, t*)` to `bezier.end` equals `min(chordLength, |end − start|)`. That distance
    /// decreases monotonically as `t` runs 0→1 for the curves this connector produces, so 20 bisection
    /// steps land well within floating-point noise.
    private func curveTrimParameter(_ bezier: CubicBezier, chordLength: CGFloat) -> CGFloat {
        let fullChord = hypot(bezier.end.x - bezier.start.x, bezier.end.y - bezier.start.y)
        let target = min(chordLength, fullChord)
        var lo: CGFloat = 0
        var hi: CGFloat = 1
        for _ in 0..<20 {
            let mid = (lo + hi) / 2
            let point = cubicPoint(bezier, at: mid)
            let dist = hypot(bezier.end.x - point.x, bezier.end.y - point.y)
            if dist > target { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// The De Casteljau LEFT subcurve of `bezier` split at `t`: `(P0, A, D, F)` where
    /// `A = lerp(P0,P1,t)`, `B = lerp(P1,P2,t)`, `C = lerp(P2,P3,t)`, `D = lerp(A,B,t)`,
    /// `E = lerp(B,C,t)`, `F = lerp(D,E,t)`. `F` is the point on the original curve at `t` (the visible
    /// path's new end); the subcurve reparameterizes the original's `[0, t]` span onto `[0, 1]`.
    private func splitCubicBezier(_ bezier: CubicBezier, at t: CGFloat) -> CubicBezier {
        func lerp(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        let a = lerp(bezier.start, bezier.c1)
        let b = lerp(bezier.c1, bezier.c2)
        let c = lerp(bezier.c2, bezier.end)
        let d = lerp(a, b)
        let e = lerp(b, c)
        let f = lerp(d, e)
        return CubicBezier(start: bezier.start, c1: a, c2: d, end: f)
    }
}
