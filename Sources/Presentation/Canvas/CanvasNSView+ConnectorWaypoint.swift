import AppKit

// MARK: - Connector waypoint (central deformation handle: hit-test / draw / commit)
//
// An elbow/curve connector that is the sole selection shows a single draggable handle at the route's
// centre. Dragging it sets the connector's *waypoint* — the relative offset of that handle from the
// midpoint of the two endpoint edge midpoints — bending the route through the dragged point. On
// mouse-up the offset commits via the ViewModel (one undo step). Straight connectors show no handle
// (the waypoint is meaningless there). The begin-press / draft state writes live in `CanvasNSView`
// (same-file `private(set)` mutation); this extension holds the read-only hit-test, drawing, and
// commit logic — mirroring `+ConnectorReconnect`.

/// Live state for a connector-waypoint drag: the connector being deformed and the cursor's current
/// world position (the handle's free position; the committed offset is this minus the endpoint
/// midpoint's midpoint).
struct ConnectorWaypointDraft {
    let connectorID: UUID
    var currentWorld: CGPoint
}

extension CanvasNSView {

    /// The sole-selected connector's central deformation handle under `viewPoint`, as its id, else
    /// `nil`. Only elbow/curve connectors have a handle; straight ones return `nil`. Reuses the edge
    /// handle's `edgeHandleRadius * 2` tolerance, like the reconnect endpoint handles.
    func connectorWaypointHandleHit(atView viewPoint: CGPoint) -> UUID? {
        guard let connector = selectedConnector,
              let handle = connectorWaypointHandleView(connector) else { return nil }
        return hypot(viewPoint.x - handle.x, viewPoint.y - handle.y) <= edgeHandleRadius * 2
            ? connector.id : nil
    }

    /// Draws the sole-selected connector's central deformation handle (elbow/curve only), or — while
    /// a waypoint drag is active — the live handle following the cursor. Called from
    /// `drawConnectorAffordances` after the endpoint handles. A distinct hollow (ring) handle marks
    /// it as the *shape* handle, visually separate from the filled endpoint reconnect handles.
    func drawConnectorWaypointAffordance() {
        guard let connector = selectedConnector else { return }
        if let draft = connectorWaypointDraft, draft.connectorID == connector.id {
            drawWaypointDragPreview(draft, connector: connector)
            return
        }
        if let handle = connectorWaypointHandleView(connector) {
            drawWaypointHandle(at: handle)
        }
    }

    /// Live deformation preview while the waypoint handle is being dragged: re-routes the connector
    /// through the cursor and strokes the resulting path, then draws the handle on the cursor — so the
    /// line bends *as it drags*, matching the sibling reconnect gesture's live preview rather than
    /// snapping into shape only on mouse-up. Falls back to the bare handle if an endpoint sticky is
    /// gone (no geometry to re-route).
    private func drawWaypointDragPreview(_ draft: ConnectorWaypointDraft, connector: ConnectorResponse) {
        let handleView = worldToView(draft.currentWorld)
        if var geo = connectorViewGeometry(connector) {
            geo.waypoint = handleView   // force the route through the dragged point, not the committed offset
            let path = connectorPath(geo, routing: connector.routing).path
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.stroke()
        }
        drawWaypointHandle(at: handleView)
    }

    /// A hollow accent ring — the deformation (waypoint) handle. Hollow so it reads distinctly from
    /// the filled endpoint reconnect handles drawn at the connector's two ends.
    private func drawWaypointHandle(at point: CGPoint) {
        let rect = CGRect(x: point.x - edgeHandleRadius, y: point.y - edgeHandleRadius,
                          width: edgeHandleRadius * 2, height: edgeHandleRadius * 2)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.stroke()
    }

    /// Commits a connector-waypoint drag: stores the offset of the dragged handle from the midpoint
    /// of the two endpoint edge midpoints (the same relative basis the geometry resolves against, so
    /// the deformed connector translates with its stickies). If an endpoint sticky has vanished the
    /// basis can't be computed, so the drag is dropped (a redraw clears the lingering preview).
    /// Before computing the offset, the dragged point is clamped outside both endpoint rects
    /// (`clampWaypointOutsideRects`, ruling 5: a waypoint dropped behind a sticky's edge commits to
    /// the nearest point outside it instead — frozen fact "カギ線は waypoint を頂点として通過する" and
    /// "付箋本体を貫通しない" can't both hold for a point actually inside a rect, ticket 805F3652 Phase
    /// 2 §C). The preview stays free (`drawWaypointDragPreview` uses `draft.currentWorld` directly),
    /// so only the committed value is affected. `waypointOffsetX/Y`'s storage/validation is otherwise
    /// unchanged, so this is still the single write path (undo stays one step).
    func commitConnectorWaypoint(_ draft: ConnectorWaypointDraft) {
        guard let connector = connectors.first(where: { $0.id == draft.connectorID }),
              let base = connectorEndpointsMidpointWorld(connector) else {
            needsDisplay = true
            return
        }
        var point = draft.currentWorld
        if let sourceRect = worldRect(stickyID: connector.sourceStickyID),
           let targetRect = worldRect(stickyID: connector.targetStickyID) {
            point = clampWaypointOutsideRects(point, sourceRect: sourceRect, targetRect: targetRect)
        }
        let offsetX = Double(point.x - base.x)
        let offsetY = Double(point.y - base.y)
        actions?.setConnectorWaypoint(id: connector.id, offsetX: offsetX, offsetY: offsetY)
    }

    /// World-space midpoint of the connector's two endpoint edge midpoints — the basis the waypoint
    /// offset is stored relative to. `nil` if either endpoint sticky is gone.
    private func connectorEndpointsMidpointWorld(_ connector: ConnectorResponse) -> CGPoint? {
        guard let sourceMid = edgeMidpointWorld(stickyID: connector.sourceStickyID, edge: connector.sourceEdge),
              let targetMid = edgeMidpointWorld(stickyID: connector.targetStickyID, edge: connector.targetEdge) else {
            return nil
        }
        return waypointOffsetBasis(sourceMid: sourceMid, targetMid: targetMid)
    }

    // MARK: Rect clamp (ticket 805F3652 Phase 2 §C)
    //
    // Pure geometry — no sticky resolution, coordinate-space-agnostic (world at commit time, world
    // again at draw time before `worldToView`) — so `commitConnectorWaypoint` above and
    // `connectorViewGeometry` (+ConnectorPath.swift) call the exact same function rather than each
    // rolling its own (review-checklist item 3).

    /// `point` pushed outside `rect` via whichever edge is nearest, plus `margin`, or returned
    /// unchanged if already outside. Ties break left/right/top/bottom (declaration order below,
    /// matching the design's Python `dict`-ordered `min`).
    private func clampOutsideRect(_ point: CGPoint, rect: CGRect, margin: CGFloat) -> CGPoint {
        guard pointStrictlyInside(point, rect: rect) else { return point }
        let distLeft = point.x - rect.minX
        let distRight = rect.maxX - point.x
        let distTop = point.y - rect.minY
        let distBottom = rect.maxY - point.y
        let nearest = min(distLeft, distRight, distTop, distBottom)
        if nearest == distLeft { return CGPoint(x: rect.minX - margin, y: point.y) }
        if nearest == distRight { return CGPoint(x: rect.maxX + margin, y: point.y) }
        if nearest == distTop { return CGPoint(x: point.x, y: rect.minY - margin) }
        return CGPoint(x: point.x, y: rect.maxY + margin)
    }

    private func pointStrictlyInside(_ point: CGPoint, rect: CGRect, eps: CGFloat = 1e-9) -> Bool {
        rect.minX + eps <= point.x && point.x <= rect.maxX - eps
            && rect.minY + eps <= point.y && point.y <= rect.maxY - eps
    }

    private func clamp2Step(_ point: CGPoint, sourceRect: CGRect, targetRect: CGRect, margin: CGFloat) -> CGPoint {
        clampOutsideRect(clampOutsideRect(point, rect: sourceRect, margin: margin), rect: targetRect, margin: margin)
    }

    private struct SeparatingGap {
        let axis: Axis
        let gap: CGFloat
        let mid: CGFloat
        enum Axis { case x, y }
    }

    /// The axis (or axes) on which `sourceRect`/`targetRect` are actually separated, with the gap size
    /// and its midpoint. Empty only when the two rects overlap (out of scope — see `safeAutoRoute`'s
    /// doc comment for the same boundary).
    private func separatingGaps(sourceRect: CGRect, targetRect: CGRect) -> [SeparatingGap] {
        var gaps: [SeparatingGap] = []
        if sourceRect.maxX <= targetRect.minX {
            gaps.append(SeparatingGap(axis: .x, gap: targetRect.minX - sourceRect.maxX,
                                      mid: (sourceRect.maxX + targetRect.minX) / 2))
        } else if targetRect.maxX <= sourceRect.minX {
            gaps.append(SeparatingGap(axis: .x, gap: sourceRect.minX - targetRect.maxX,
                                      mid: (targetRect.maxX + sourceRect.minX) / 2))
        }
        if sourceRect.maxY <= targetRect.minY {
            gaps.append(SeparatingGap(axis: .y, gap: targetRect.minY - sourceRect.maxY,
                                      mid: (sourceRect.maxY + targetRect.minY) / 2))
        } else if targetRect.maxY <= sourceRect.minY {
            gaps.append(SeparatingGap(axis: .y, gap: sourceRect.minY - targetRect.maxY,
                                      mid: (targetRect.maxY + sourceRect.minY) / 2))
        }
        return gaps
    }

    /// The waypoint clamp: two-step push-outside (source, then target; see `clampOutsideRect`), and —
    /// only if that still leaves the point inside either rect, which happens when the two rects are
    /// closer together than `margin` — a fallback that snaps the narrower separating axis to the gap's
    /// midpoint (`separatingGaps`). Deterministic (no randomness) and, at the 2-step/fallback
    /// boundary, moves only as far as `margin` from the 2-step result — smaller and smoother than
    /// pushing to the union bbox's perimeter (design rounds 4–5 measured ~5× larger jumps there).
    /// Returns the 2-step result unclamped when the rects overlap (`separatingGaps` empty) — out of
    /// scope, not a crash (ticket 805F3652 Phase 2 §B/§C "既知の限界").
    func clampWaypointOutsideRects(_ point: CGPoint, sourceRect: CGRect, targetRect: CGRect,
                                   margin: CGFloat = connectorRectMargin) -> CGPoint {
        let final = clamp2Step(point, sourceRect: sourceRect, targetRect: targetRect, margin: margin)
        guard pointStrictlyInside(final, rect: sourceRect) || pointStrictlyInside(final, rect: targetRect) else {
            return final
        }
        guard let chosen = separatingGaps(sourceRect: sourceRect, targetRect: targetRect)
            .min(by: { $0.gap < $1.gap }) else {
            return final
        }
        switch chosen.axis {
        case .x: return CGPoint(x: chosen.mid, y: final.y)
        case .y: return CGPoint(x: final.x, y: chosen.mid)
        }
    }
}
