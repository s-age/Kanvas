import AppKit

// MARK: - Automatic elbow route: same-axis fold guard (Phase 1, ticket 805F3652)
//
// The automatic (no-waypoint) elbow route in `elbowPoints` (+ConnectorPath.swift) steps both
// endpoints out along their edges' outward normals by a shared offset, then joins them with one
// corner. When source and target sit on the same axis (both top/bottom, or both left/right) and the
// offset overshoots the endpoints' separation on that axis, the route's tail folds back over itself
// instead of turning once. This file holds the fold detection plus two remedies, chosen so the
// non-folding case (including the AF4CE767-guaranteed same-level bracket) is untouched: capping the
// offset for an opposite-sign edge pair (e.g. bottom→top), and an outer "shelf" route for a
// same-sign pair (e.g. top→top) where capping alone would degenerate to a flat, edge-hugging leg.
// This fold guard runs BEFORE the rect-aware detour in `+ConnectorRectRouting.swift` (Phase 2 §B):
// `elbowPoints` always computes a fold-free "Phase 1 route" here first, then hands it to
// `safeAutoRoute` to accept as-is or replace with a detour.

/// A same-axis source/target edge pair's fold-relevant scalars: `delta` is the endpoints' signed
/// separation along the shared axis (`end − start`), `s1`/`s2` are the source/target edges' outward
/// normal components along that axis (`±1`). Absent for a different-axis pair (e.g. top×left), which
/// always turns at a right angle and can never fold.
private struct ElbowAxisPair {
    let delta: CGFloat
    let s1: CGFloat
    let s2: CGFloat
}

extension CanvasNSView {

    private func elbowAxisPair(_ geo: ConnectorViewGeometry) -> ElbowAxisPair? {
        let vertical: Set<CanvasEdgeResponse> = [.top, .bottom]
        let horizontal: Set<CanvasEdgeResponse> = [.left, .right]
        if vertical.contains(geo.sourceEdge), vertical.contains(geo.targetEdge) {
            return ElbowAxisPair(delta: geo.end.y - geo.start.y,
                                 s1: outwardNormal(geo.sourceEdge).dy, s2: outwardNormal(geo.targetEdge).dy)
        }
        if horizontal.contains(geo.sourceEdge), horizontal.contains(geo.targetEdge) {
            return ElbowAxisPair(delta: geo.end.x - geo.start.x,
                                 s1: outwardNormal(geo.sourceEdge).dx, s2: outwardNormal(geo.targetEdge).dx)
        }
        return nil
    }

    /// Whether the automatic route folds back on itself at `offset`: `(Δ + offset·(s2−s1))·s2 > 0`.
    private func elbowAxisFolds(_ axis: ElbowAxisPair, offset: CGFloat) -> Bool {
        (axis.delta + offset * (axis.s2 - axis.s1)) * axis.s2 > 0
    }

    /// The step-out offset the automatic elbow route should use: `fullOffset` unchanged unless the
    /// pair is same-axis, opposite-sign, and folding at that offset — in which case it's capped so the
    /// corner lands exactly on the fold boundary instead of past it (`Δy/2` in the reported bottom→top
    /// case). A same-sign folding pair (e.g. top→top) is handled separately by `elbowAutoRouteShelf`
    /// instead, which keeps the offset full.
    func elbowAutoRouteOffset(_ geo: ConnectorViewGeometry, fullOffset: CGFloat) -> CGFloat {
        guard let axis = elbowAxisPair(geo), axis.s1 != axis.s2, elbowAxisFolds(axis, offset: fullOffset)
        else { return fullOffset }
        let capped = -axis.delta * axis.s2 / ((axis.s2 - axis.s1) * axis.s2)
        return min(max(capped, 0), fullOffset)
    }

    /// The automatic route's 4-point outer-shelf polyline for a same-sign folding pair (e.g. top→top
    /// with the target directly above): `[start, ⟂, ⟂, end]`, where both perpendicular corners sit on
    /// whichever endpoint's full-offset step-out lands further outward — so both endpoints keep at
    /// least `fullOffset` of clearance and the first/last segment stays perpendicular to its edge.
    /// `nil` when the pair isn't same-axis/same-sign, or doesn't fold at `fullOffset` (the standard
    /// sPrime/corner/ePrime route already doesn't fold there).
    func elbowAutoRouteShelf(_ geo: ConnectorViewGeometry, fullOffset: CGFloat) -> [CGPoint]? {
        guard let axis = elbowAxisPair(geo), axis.s1 == axis.s2, elbowAxisFolds(axis, offset: fullOffset)
        else { return nil }
        let sourceVertical = geo.sourceEdge == .top || geo.sourceEdge == .bottom
        if sourceVertical {
            let base = axis.s2 < 0 ? min(geo.start.y, geo.end.y) : max(geo.start.y, geo.end.y)
            let shelf = base + axis.s2 * fullOffset
            return [geo.start, CGPoint(x: geo.start.x, y: shelf), CGPoint(x: geo.end.x, y: shelf), geo.end]
        }
        let base = axis.s2 < 0 ? min(geo.start.x, geo.end.x) : max(geo.start.x, geo.end.x)
        let shelf = base + axis.s2 * fullOffset
        return [geo.start, CGPoint(x: shelf, y: geo.start.y), CGPoint(x: shelf, y: geo.end.y), geo.end]
    }
}
