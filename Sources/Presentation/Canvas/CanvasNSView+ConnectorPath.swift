import AppKit

// MARK: - Connector path construction + distance helpers
//
// Builds a connector's drawn path and hit-test polyline in view space from its resolved geometry,
// honouring an optional waypoint (the central deformation point): elbow routes source→waypoint→
// target as two orthogonal legs, curve bends its control points through the waypoint. Split out of
// `+Connectors` for the file_length budget; the structs below are shared between the two files.

/// View-space geometry of a connector: its two endpoints, the edges they attach to, and an optional
/// waypoint (the central deformation point in view space, when the connector carries one). Bundles
/// the values so the path builders stay within the parameter budget. `waypoint == nil` ⇒ the
/// automatic (un-deformed) route.
struct ConnectorViewGeometry {
    let start: CGPoint
    let end: CGPoint
    let sourceEdge: CanvasEdgeResponse
    let targetEdge: CanvasEdgeResponse
    var waypoint: CGPoint?
}

/// The four control points of a cubic Bézier, bundled so `sampledBezier` takes one geometry arg.
struct CubicBezier {
    let start: CGPoint
    let c1: CGPoint
    let c2: CGPoint
    let end: CGPoint
}

extension CanvasNSView {

    /// Builds the connector's drawn path (view space) and the tangent at its target end (for the
    /// arrowhead). `straight` is a line; `elbow` is an orthogonal H-V-H / V-H-V route; `curve` is a
    /// cubic Bézier with control points along each edge's outward normal.
    func connectorPath(_ geo: ConnectorViewGeometry, routing: ConnectorRoutingResponse)
        -> (path: NSBezierPath, endTangent: CGVector) {
        let path = NSBezierPath()
        switch routing {
        case .straight:
            path.move(to: geo.start)
            path.line(to: geo.end)
            return (path, CGVector(dx: geo.end.x - geo.start.x, dy: geo.end.y - geo.start.y))
        case .elbow:
            let pts = elbowPoints(geo)
            path.move(to: pts[0])
            for p in pts.dropFirst() { path.line(to: p) }
            let prev = pts[pts.count - 2]
            return (path, CGVector(dx: geo.end.x - prev.x, dy: geo.end.y - prev.y))
        case .curve:
            let bezier = curve(geo)
            path.move(to: bezier.start)
            path.curve(to: bezier.end, controlPoint1: bezier.c1, controlPoint2: bezier.c2)
            return (path, CGVector(dx: bezier.end.x - bezier.c2.x, dy: bezier.end.y - bezier.c2.y))
        }
    }

    /// View-space polyline approximating a connector's path (for hit-testing). Curves are sampled.
    func connectorViewPolyline(_ connector: ConnectorResponse) -> [CGPoint]? {
        guard let geo = connectorViewGeometry(connector) else { return nil }
        switch connector.routing {
        case .straight: return [geo.start, geo.end]
        case .elbow: return elbowPoints(geo)
        case .curve: return sampledBezier(curve(geo), steps: 16)
        }
    }

    /// Resolves a connector's two endpoints to view space, or `nil` if a sticky is gone. When the
    /// connector carries a waypoint offset *and* its routing deforms (elbow/curve), the waypoint's
    /// view position is resolved too (world midpoint of the two endpoint mids + offset). A `straight`
    /// connector ignores the offset (no deformation, no handle), so its geometry carries no waypoint.
    func connectorViewGeometry(_ connector: ConnectorResponse) -> ConnectorViewGeometry? {
        guard let sourceMid = edgeMidpointWorld(stickyID: connector.sourceStickyID, edge: connector.sourceEdge),
              let targetMid = edgeMidpointWorld(stickyID: connector.targetStickyID, edge: connector.targetEdge) else {
            return nil
        }
        var waypoint: CGPoint?
        if connector.routing != .straight,
           let dx = connector.waypointOffsetX, let dy = connector.waypointOffsetY {
            let base = waypointOffsetBasis(sourceMid: sourceMid, targetMid: targetMid)
            waypoint = worldToView(CGPoint(x: base.x + dx, y: base.y + dy))
        }
        return ConnectorViewGeometry(
            start: worldToView(sourceMid), end: worldToView(targetMid),
            sourceEdge: connector.sourceEdge, targetEdge: connector.targetEdge,
            waypoint: waypoint
        )
    }

    /// The world-space basis the waypoint offset is stored relative to: the midpoint of the two
    /// endpoint edge midpoints. Defined once here and shared by the draw path
    /// (`connectorViewGeometry`, which adds the offset to resolve the handle) and the commit path
    /// (`connectorEndpointsMidpointWorld` in `+ConnectorWaypoint`, which subtracts it to derive the
    /// offset), so both sides agree on the same origin.
    func waypointOffsetBasis(sourceMid: CGPoint, targetMid: CGPoint) -> CGPoint {
        CGPoint(x: (sourceMid.x + targetMid.x) / 2, y: (sourceMid.y + targetMid.y) / 2)
    }

    /// The view-space position of the connector's central deformation handle: the waypoint when one
    /// is set, else the natural centre of the automatic route (elbow's corner / curve's t=0.5 point)
    /// so the handle appears where a drag will begin to bend the line. `nil` for a `straight`
    /// connector (no handle) or a connector whose endpoints can't resolve. Used by the waypoint
    /// drawing + hit-testing in `+ConnectorWaypoint`.
    func connectorWaypointHandleView(_ connector: ConnectorResponse) -> CGPoint? {
        guard connector.routing != .straight, let geo = connectorViewGeometry(connector) else { return nil }
        if let waypoint = geo.waypoint { return waypoint }
        // Only elbow/curve reach here (the guard rejects straight); `default` covers the impossible
        // straight case without an unreachable `case .straight` branch.
        switch connector.routing {
        case .elbow:
            // The point halfway along the route by arc length. The automatic route now has three
            // interior points ([start, sPrime, corner, ePrime, end]), so a fixed interior-vertex
            // midpoint would bias toward the source; walking half the polyline's length lands the
            // handle at the route's true geometric centre regardless of vertex count (ticket
            // AF4CE767).
            return polylineMidpoint(elbowPoints(geo))
        case .curve:
            return cubicPoint(curve(geo), at: 0.5)
        default:
            return nil
        }
    }

    /// The point on a cubic Bézier at parameter `t` (seats the curve handle at t=0.5; also the per-
    /// step kernel of `sampledBezier`).
    func cubicPoint(_ bezier: CubicBezier, at t: CGFloat) -> CGPoint {
        let u = 1 - t
        let w0 = u * u * u, w1 = 3 * u * u * t, w2 = 3 * u * t * t, w3 = t * t * t
        return CGPoint(
            x: w0 * bezier.start.x + w1 * bezier.c1.x + w2 * bezier.c2.x + w3 * bezier.end.x,
            y: w0 * bezier.start.y + w1 * bezier.c1.y + w2 * bezier.c2.y + w3 * bezier.end.y
        )
    }

    func elbowPoints(_ geo: ConnectorViewGeometry) -> [CGPoint] {
        // With a waypoint set, route source→waypoint→target as two orthogonal legs, the source leg
        // leaving its edge perpendicular and the arriving leg docking into the target edge
        // perpendicular (so the connector still "exits"/"enters" the stickies cleanly). Each leg turns
        // its perpendicular excursion through the *waypoint's* off-axis coordinate (not the endpoint's
        // own), at a midpoint corner that straddles the waypoint — so the two legs' parallel
        // excursions sit at different positions and never retrace one another. Without a waypoint, the
        // classic single-bend H-V-H / V-H-V midline.
        if let waypoint = geo.waypoint {
            return [geo.start]
                + leavingElbowLeg(from: geo.start, to: waypoint, leavingEdge: geo.sourceEdge)
                + [waypoint]
                + arrivingElbowLeg(from: waypoint, to: geo.end, arrivingEdge: geo.targetEdge)
                + [geo.end]
        }
        // Automatic (un-deformed) route. Step out of *both* edges along their outward normals by the
        // same offset `o` that `curve(_:)` uses, so the route brackets out by a guaranteed height even
        // when the two endpoints share an axis (the old "bend to the midline" route collapsed to a flat
        // line there — see ticket AF4CE767). The corner joins the two stepped-out points orthogonally,
        // turning on whichever axis the *source* normal points along.
        let offset = connectorNormalOffset(start: geo.start, end: geo.end)
        let n1 = outwardNormal(geo.sourceEdge)
        let n2 = outwardNormal(geo.targetEdge)
        let sPrime = CGPoint(x: geo.start.x + n1.dx * offset, y: geo.start.y + n1.dy * offset)
        let ePrime = CGPoint(x: geo.end.x + n2.dx * offset, y: geo.end.y + n2.dy * offset)
        // Source normal vertical (top/bottom) ⇒ the corner shares the source's stepped-out y and the
        // target's stepped-out x; horizontal ⇒ the axis-mirror.
        let sourceVertical = geo.sourceEdge == .top || geo.sourceEdge == .bottom
        let corner = sourceVertical
            ? CGPoint(x: ePrime.x, y: sPrime.y)
            : CGPoint(x: sPrime.x, y: ePrime.y)
        return dedupedPolyline([geo.start, sPrime, corner, ePrime, geo.end])
    }

    /// The perpendicular step-out distance shared by the automatic elbow route and `curve(_:)`:
    /// `max(40, dist × 0.4)` over the straight-line endpoint distance. Extracted so the two routers
    /// can't drift (ticket AF4CE767).
    func connectorNormalOffset(start: CGPoint, end: CGPoint) -> CGFloat {
        max(40, hypot(end.x - start.x, end.y - start.y) * 0.4)
    }

    /// Drops consecutive duplicate points (zero-length segments) from a polyline. A degenerate
    /// automatic-elbow route (e.g. top→top at the same level, where the corner coincides with a
    /// stepped-out point) produces such duplicates; removing them keeps the drawn path and the
    /// arrowhead tangent (`pts[count-2]`) well-defined. Guarantees `count >= 2` for any input whose
    /// endpoints differ, so the path still has a direction.
    private func dedupedPolyline(_ points: [CGPoint]) -> [CGPoint] {
        var result: [CGPoint] = []
        for p in points where result.last.map({ $0 != p }) ?? true {
            result.append(p)
        }
        return result
    }

    /// The interior corners of the *source* leg from `from` to the waypoint `to`, leaving `from`
    /// perpendicular to `leavingEdge`. Two corners, turning the perpendicular excursion through the
    /// waypoint's own off-axis coordinate at a midpoint that straddles it: for a horizontal edge
    /// (.left/.right ⇒ leave horizontally) the leg runs `from → (midX, from.y) → (midX, to.y) → to`
    /// with `midX` halfway between `from.x` and `to.x`; for a vertical edge the axis-mirror. Routing
    /// the climb at `midX` (rather than at `to.x`, as a single-corner L would) keeps it clear of the
    /// arriving leg's descent, so a route whose endpoints share an axis no longer retraces itself.
    private func leavingElbowLeg(from: CGPoint, to: CGPoint, leavingEdge edge: CanvasEdgeResponse)
        -> [CGPoint] {
        switch edge {
        case .left, .right:                          // leave horizontally, climb to waypoint.y at midX
            let midX = (from.x + to.x) / 2
            return [CGPoint(x: midX, y: from.y), CGPoint(x: midX, y: to.y)]
        case .top, .bottom:                          // leave vertically, slide to waypoint.x at midY
            let midY = (from.y + to.y) / 2
            return [CGPoint(x: from.x, y: midY), CGPoint(x: to.x, y: midY)]
        }
    }

    /// The interior corners of the leg *into* the target, so the connector *arrives* perpendicular to
    /// `arrivingEdge` — the LAST segment (into `to`) runs along the edge's outward normal, matching
    /// the un-deformed elbow's docking direction. Mirror of `leavingElbowLeg`: from the waypoint
    /// `from`, descend off the waypoint's axis at a midpoint that straddles it, then dock. For a
    /// horizontal target (.left/.right ⇒ arrive horizontally) the leg runs
    /// `from → (midX, from.y) → (midX, to.y) → to` with `midX` halfway between `from.x` and `to.x`,
    /// so the last segment is horizontal (shares the target's y) and the descent at `midX` sits clear
    /// of the source leg's climb — no retraced segment. A top/bottom target is the axis-mirror.
    private func arrivingElbowLeg(from: CGPoint, to: CGPoint, arrivingEdge edge: CanvasEdgeResponse)
        -> [CGPoint] {
        switch edge {
        case .left, .right:                          // descend at midX, then dock horizontally
            let midX = (from.x + to.x) / 2
            return [CGPoint(x: midX, y: from.y), CGPoint(x: midX, y: to.y)]
        case .top, .bottom:                          // slide at midY, then dock vertically
            let midY = (from.y + to.y) / 2
            return [CGPoint(x: from.x, y: midY), CGPoint(x: to.x, y: midY)]
        }
    }

    func curve(_ geo: ConnectorViewGeometry) -> CubicBezier {
        let offset = connectorNormalOffset(start: geo.start, end: geo.end)
        let n1 = outwardNormal(geo.sourceEdge)
        let n2 = outwardNormal(geo.targetEdge)
        let a1 = CGPoint(x: geo.start.x + n1.dx * offset, y: geo.start.y + n1.dy * offset)
        let a2 = CGPoint(x: geo.end.x + n2.dx * offset, y: geo.end.y + n2.dy * offset)
        guard let waypoint = geo.waypoint else {
            return CubicBezier(start: geo.start, c1: a1, c2: a2, end: geo.end)
        }
        // The curve must *pass through* the waypoint at t=0.5 (the handle is drawn there). For a cubic
        // B(0.5) = (start + 3·c1 + 3·c2 + end) / 8, so the control points must satisfy
        // c1 + c2 = (8·waypoint − start − end) / 3. Shift both edge-normal anchors (a1, a2) by the
        // *same* vector `d` to meet that sum: this preserves each end's outward-normal tangent
        // direction (start→c1 and end→c2 keep their relative offsets) while seating B(0.5) exactly on
        // the waypoint, independent of the chosen `offset`. Worked: start=(0,0) end=(100,0)
        // waypoint=(50,60) ⇒ B(0.5) = (50,60), on the handle (was (50,22.5), ~37px adrift).
        let targetSum = CGPoint(x: (8 * waypoint.x - geo.start.x - geo.end.x) / 3,
                                y: (8 * waypoint.y - geo.start.y - geo.end.y) / 3)
        let d = CGPoint(x: (targetSum.x - a1.x - a2.x) / 2, y: (targetSum.y - a1.y - a2.y) / 2)
        return CubicBezier(
            start: geo.start,
            c1: CGPoint(x: a1.x + d.x, y: a1.y + d.y),
            c2: CGPoint(x: a2.x + d.x, y: a2.y + d.y),
            end: geo.end
        )
    }

    func sampledBezier(_ bezier: CubicBezier, steps: Int) -> [CGPoint] {
        (0...steps).map { cubicPoint(bezier, at: CGFloat($0) / CGFloat(steps)) }
    }

    /// The point halfway along a polyline by arc length (its geometric centre, robust to uneven
    /// vertex spacing). Walks the segments accumulating length until half the total is reached, then
    /// interpolates within that segment. Returns the sole point for a 1-point input, or the endpoint
    /// midpoint for a zero-length (all-coincident) polyline.
    func polylineMidpoint(_ points: [CGPoint]) -> CGPoint {
        guard let first = points.first else { return .zero }
        guard points.count >= 2 else { return first }
        var total: CGFloat = 0
        for i in 0..<(points.count - 1) {
            total += hypot(points[i + 1].x - points[i].x, points[i + 1].y - points[i].y)
        }
        guard total > 0 else {
            let last = points[points.count - 1]
            return CGPoint(x: (first.x + last.x) / 2, y: (first.y + last.y) / 2)
        }
        let half = total / 2
        var travelled: CGFloat = 0
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            let segLength = hypot(b.x - a.x, b.y - a.y)
            if travelled + segLength >= half {
                let t = segLength > 0 ? (half - travelled) / segLength : 0
                return CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
            travelled += segLength
        }
        return points[points.count - 1]
    }

    /// Shortest distance from `point` to a polyline (the minimum over its segments). Per-segment
    /// distance reuses `distance(from:toSegment:)` from `CanvasNSView+Geometry`.
    func distance(from point: CGPoint, toPolyline points: [CGPoint]) -> CGFloat {
        guard points.count >= 2 else {
            return points.first.map { hypot(point.x - $0.x, point.y - $0.y) } ?? .greatestFiniteMagnitude
        }
        var best = CGFloat.greatestFiniteMagnitude
        for i in 0..<(points.count - 1) {
            best = min(best, distance(from: point, toSegment: points[i], points[i + 1]))
        }
        return best
    }
}
