import AppKit

// MARK: - Connectors (draw / hit-test / grow)
//
// A connector links two stickies edge-to-edge. Each endpoint is resolved live to its sticky's edge
// midpoint, so the connector follows the stickies as they move/resize. Connectors render in their
// own pass behind every sticky/shape (they take no part in the `items` z-order), and are grown by
// dragging out from an edge handle on the selected sticky. Dropping on a sticky links it; dropping
// on empty canvas grows a new sticky (handled by the ViewModel).

/// Live state for a connector-grow gesture: the source sticky + edge it sprang from, and the
/// cursor's current world position (the preview's free end).
struct ConnectorDraft {
    let sourceStickyID: UUID
    let sourceEdge: CanvasEdgeResponse
    var currentWorld: CGPoint
}

/// Arrowhead dimensions (view points): the wedge's length and its half-width at the base.
private struct ArrowMetrics {
    let length: CGFloat
    let halfWidth: CGFloat
}

extension CanvasNSView {

    /// View radius of an edge handle (zoom-independent, like the resize handle).
    var edgeHandleRadius: CGFloat { 5 }

    private var allEdges: [CanvasEdgeResponse] { [.top, .bottom, .left, .right] }

    // MARK: Geometry

    /// World-space midpoint of `edge` on a sticky's live rect, or `nil` if the sticky is gone.
    /// Resolves the sticky via the O(1) `stickyByID` index — this runs twice per connector per draw.
    func edgeMidpointWorld(stickyID: UUID, edge: CanvasEdgeResponse) -> CGPoint? {
        guard let sticky = stickyByID[stickyID] else { return nil }
        return edgeMidpoint(of: worldRect(for: .sticky(sticky)), edge: edge)
    }

    /// Midpoint of `edge` on `rect`. The view is flipped (y grows downward), so `top` is `minY`.
    func edgeMidpoint(of rect: CGRect, edge: CanvasEdgeResponse) -> CGPoint {
        switch edge {
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .left: CGPoint(x: rect.minX, y: rect.midY)
        case .right: CGPoint(x: rect.maxX, y: rect.midY)
        }
    }

    /// Outward unit normal of `edge` (y grows downward), used for curve control points.
    func outwardNormal(_ edge: CanvasEdgeResponse) -> CGVector {
        switch edge {
        case .top: CGVector(dx: 0, dy: -1)
        case .bottom: CGVector(dx: 0, dy: 1)
        case .left: CGVector(dx: -1, dy: 0)
        case .right: CGVector(dx: 1, dy: 0)
        }
    }

    /// The edge of `rect` whose midpoint is closest to `point` (used to pick a drop target's edge).
    func nearestEdge(of rect: CGRect, to point: CGPoint) -> CanvasEdgeResponse {
        allEdges.min { a, b in
            let pa = edgeMidpoint(of: rect, edge: a)
            let pb = edgeMidpoint(of: rect, edge: b)
            return hypot(point.x - pa.x, point.y - pa.y) < hypot(point.x - pb.x, point.y - pb.y)
        } ?? .left
    }

    /// The edge of a sticky centred at `origin` that faces `target` (used for a freshly-grown
    /// sticky, whose rect isn't known yet — pick by dominant direction). Sibling of `aimedEdge`'s
    /// dominant-axis branch (+ConnectorReconnect): same flipped-y edge mapping, but this compares
    /// raw deltas (no rect to normalise against) — they intentionally don't share an implementation.
    func edgeFacing(from origin: CGPoint, toward target: CGPoint) -> CanvasEdgeResponse {
        let dx = target.x - origin.x
        let dy = target.y - origin.y
        if abs(dx) >= abs(dy) { return dx >= 0 ? .right : .left }
        return dy >= 0 ? .bottom : .top
    }

    // MARK: Edge handles (on the selected sticky)

    /// The selected sticky's edge handle under `viewPoint`, as (sticky id, edge), else `nil`.
    func edgeHandleHit(atView viewPoint: CGPoint) -> (stickyID: UUID, edge: CanvasEdgeResponse)? {
        guard let selectedID = soleSelectedID, let sticky = stickyByID[selectedID] else {
            return nil
        }
        let rect = viewRect(for: .sticky(sticky))
        for edge in allEdges {
            let p = edgeMidpoint(of: rect, edge: edge)
            if hypot(viewPoint.x - p.x, viewPoint.y - p.y) <= edgeHandleRadius * 2 {
                return (sticky.id, edge)
            }
        }
        return nil
    }

    // MARK: Hit-testing

    /// The frontmost connector whose path passes within the hit tolerance of `worldPoint`, else
    /// `nil`. Connectors draw behind items, so the canvas consults this only after `item(atWorld:)`
    /// misses.
    func connector(atWorld worldPoint: CGPoint) -> ConnectorResponse? {
        let viewPoint = worldToView(worldPoint)
        for connector in connectors.reversed() {
            guard let points = connectorViewPolyline(connector) else { continue }
            if distance(from: viewPoint, toPolyline: points) <= lineHitTolerance { return connector }
        }
        return nil
    }

    // MARK: Drawing

    /// Draws every connector intersecting `dirtyRect`, behind the items. Called from `draw(_:)`
    /// before the items loop. Off-screen connectors are culled (their endpoints' bounding box,
    /// padded for curve bulge + arrowhead, against the redraw rect) so a pan/zoom over a large board
    /// only pays for the connectors actually on screen. The adaptive default-stroke colour (for
    /// unset-background default connectors) depends only on the system background, not per-connector
    /// data, so it is resolved once here and passed down rather than recomputed per connector.
    func drawConnectors(in dirtyRect: CGRect) {
        let adaptiveDefault = adaptiveDefaultStrokeColor()
        // Resolve each connector's geometry once: the cull and the draw both need it, so the loop
        // threads the already-resolved geometry into `drawConnector` rather than re-resolving both
        // endpoints (via the `stickyByID` index + `worldToView`) a second time per visible connector.
        for connector in connectors {
            guard let geo = connectorViewGeometry(connector),
                  connectorVisibleBounds(geo, strokeWidth: connector.strokeWidth).intersects(dirtyRect)
            else { continue }
            drawConnector(connector, geometry: geo, adaptiveDefault: adaptiveDefault)
        }
    }

    /// The bounding box of `geo`'s drawn path, padded so `intersects(dirtyRect)` never culls a
    /// visible connector. Conservative: a cubic Bézier stays within the convex hull of its control
    /// points, which extend at most `max(40, dist × 0.4)` outward from the endpoints (see `curve`),
    /// so padding the endpoint bounding box by that plus the arrowhead length covers the whole path.
    /// A waypoint (deformation handle) can sit outside that box, so it is unioned in first — the
    /// deformed route stays within the convex hull of {endpoints, waypoint, control points}. The
    /// padding is always ≥ 40, so the box is never empty (no zero-area `intersects` pitfall).
    private func connectorVisibleBounds(_ geo: ConnectorViewGeometry, strokeWidth: Double) -> CGRect {
        var bounds = CGRect(x: min(geo.start.x, geo.end.x), y: min(geo.start.y, geo.end.y),
                            width: abs(geo.end.x - geo.start.x), height: abs(geo.end.y - geo.start.y))
        if let waypoint = geo.waypoint {
            bounds = bounds.union(CGRect(origin: waypoint, size: .zero))
        }
        let distance = hypot(geo.end.x - geo.start.x, geo.end.y - geo.start.y)
        let pad = max(40, distance * 0.4) + arrowMetrics(width: max(CGFloat(strokeWidth) * scale, 0.5)).length
        return bounds.insetBy(dx: -pad, dy: -pad)
    }

    private func drawConnector(_ connector: ConnectorResponse, geometry geo: ConnectorViewGeometry,
                               adaptiveDefault: NSColor) {
        let (fullPath, endTangent) = connectorPath(geo, routing: connector.routing)

        let selected = isSelected(connector.id)
        let color = selected ? NSColor.controlAccentColor
            : ConnectorStrokeRendering.strokeColor(forHex: connector.strokeColorHex,
                                                   adaptiveDefault: adaptiveDefault)
        let width = max(CGFloat(connector.strokeWidth) * scale, 0.5)

        // For an arrow cap, stop the stroke at the arrowhead's base so the line meets the head's
        // back edge cleanly (instead of poking into its side along a curve's changing tangent).
        let strokePath: NSBezierPath
        let arrow = connector.cap == .arrow ? arrowMetrics(width: width) : nil
        if let arrow {
            let backEnd = pointBack(from: geo.end, along: endTangent, by: arrow.length)
            let trimmed = ConnectorViewGeometry(start: geo.start, end: backEnd,
                                                sourceEdge: geo.sourceEdge, targetEdge: geo.targetEdge)
            strokePath = connectorPath(trimmed, routing: connector.routing).path
        } else {
            strokePath = fullPath
        }
        color.setStroke()
        strokePath.lineWidth = selected ? width + 1 : width
        strokePath.lineCapStyle = .round
        strokePath.lineJoinStyle = .round
        strokePath.stroke()

        if let arrow {
            drawArrowhead(at: geo.end, direction: endTangent, metrics: arrow, color: color)
        }
    }

    /// The draw-time adaptive colour for an unset-background default connector: `#333` on a light
    /// appearance, `#ddd` on a dark one, picked from the cached `canvasBackgroundColor` luminance.
    /// In the unset-background case that cache is the dynamic `windowBackgroundColor`, resolved live
    /// in the draw context's appearance — so the pick follows a light/dark toggle with zero
    /// staleness while reusing the cache instead of re-reading the system colour per connector.
    /// Matches `ContrastColor.readableHex`'s `0.6` threshold (Domain unreachable here).
    private func adaptiveDefaultStrokeColor() -> NSColor {
        let hex = perceptualLuminance(of: canvasBackgroundColor) > 0.6
            ? ConnectorAppearance.onLightStrokeHex
            : ConnectorAppearance.onDarkStrokeHex
        return NSColor(hex: hex)
    }

    /// Arrowhead length + half-width for a given stroke width. Grows with the stroke but floored so
    /// a thin line still gets a head that reads; the ~0.84:1 width:length keeps it a compact wedge.
    private func arrowMetrics(width: CGFloat) -> ArrowMetrics {
        let length = max(12, width * 3.5)
        return ArrowMetrics(length: length, halfWidth: length * 0.42)
    }

    /// `point` moved back `amount` against `direction` (used to trim a stroke to the arrowhead base).
    private func pointBack(from point: CGPoint, along direction: CGVector, by amount: CGFloat) -> CGPoint {
        let len = hypot(direction.dx, direction.dy)
        guard len > 0.0001 else { return point }
        return CGPoint(x: point.x - direction.dx / len * amount, y: point.y - direction.dy / len * amount)
    }

    /// Edge handles on the selected sticky + the in-progress grow preview. Drawn on top of items.
    func drawConnectorAffordances() {
        if let selectedID = soleSelectedID, let sticky = stickyByID[selectedID] {
            let rect = viewRect(for: .sticky(sticky))
            for edge in allEdges { drawEdgeHandle(at: edgeMidpoint(of: rect, edge: edge)) }
        }
        if let draft = connectorDraft,
           let start = edgeMidpointWorld(stickyID: draft.sourceStickyID, edge: draft.sourceEdge) {
            let startView = worldToView(start)
            let endView = worldToView(draft.currentWorld)
            let tangent = CGVector(dx: endView.x - startView.x, dy: endView.y - startView.y)
            let arrow = arrowMetrics(width: 2)
            let backEnd = pointBack(from: endView, along: tangent, by: arrow.length)
            let path = NSBezierPath()
            path.move(to: startView)
            path.line(to: backEnd)
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.stroke()
            drawArrowhead(at: endView, direction: tangent, metrics: arrow, color: .controlAccentColor)
        }
        drawConnectorEndpointAffordances()
        drawConnectorWaypointAffordance()
    }

    func drawEdgeHandle(at point: CGPoint) {
        let rect = CGRect(x: point.x - edgeHandleRadius, y: point.y - edgeHandleRadius,
                          width: edgeHandleRadius * 2, height: edgeHandleRadius * 2)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.controlAccentColor.setFill()
        path.fill()
        NSColor.windowBackgroundColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    private func drawArrowhead(at tip: CGPoint, direction: CGVector,
                               metrics: ArrowMetrics, color: NSColor) {
        let len = hypot(direction.dx, direction.dy)
        guard len > 0.0001 else { return }
        let ux = direction.dx / len
        let uy = direction.dy / len
        let baseX = tip.x - ux * metrics.length
        let baseY = tip.y - uy * metrics.length
        // Perpendicular to the travel direction.
        let px = -uy
        let py = ux
        let path = NSBezierPath()
        path.move(to: tip)
        path.line(to: CGPoint(x: baseX + px * metrics.halfWidth, y: baseY + py * metrics.halfWidth))
        path.line(to: CGPoint(x: baseX - px * metrics.halfWidth, y: baseY - py * metrics.halfWidth))
        path.close()
        color.setFill()
        path.fill()
    }

    // MARK: Commit a grow gesture

    /// Commits the dragged-out connector: links the sticky under the cursor, or grows a new sticky
    /// at the drop point when the cursor is over empty canvas.
    ///
    /// When the drop lands on an existing sticky the target edge is chosen **manually by aim** —
    /// the same `aimedEdge` decision reconnect uses (+ConnectorReconnect): a drop in an edge's
    /// outer band honours that edge, while a central drop falls back to the **automatic** edge
    /// nearest the source's midpoint (the prior behaviour), so a centre-drop still behaves as
    /// before. The empty-canvas branch grows a new sticky whose rect is not yet known, so it keeps
    /// `edgeFacing` (dominant direction toward the source) — there is no rect to aim within.
    func commitConnectorDraft(_ draft: ConnectorDraft) {
        let dropWorld = draft.currentWorld
        let sourceMid = edgeMidpointWorld(stickyID: draft.sourceStickyID, edge: draft.sourceEdge) ?? dropWorld

        let targetEdge: CanvasEdgeResponse
        let existingTargetStickyID: UUID?
        if case .sticky(let target)? = item(atWorld: dropWorld), target.id != draft.sourceStickyID {
            let targetRect = worldRect(for: .sticky(target))
            targetEdge = aimedEdge(of: targetRect, dropWorld: dropWorld)
                ?? nearestEdge(of: targetRect, to: sourceMid)
            existingTargetStickyID = target.id
        } else {
            targetEdge = edgeFacing(from: dropWorld, toward: sourceMid)
            existingTargetStickyID = nil
        }
        actions?.growConnector(ConnectorGrowGesture(
            sourceStickyID: draft.sourceStickyID, sourceEdge: draft.sourceEdge.rawValue,
            targetEdge: targetEdge.rawValue, existingTargetStickyID: existingTargetStickyID,
            dropWorldX: Double(dropWorld.x), dropWorldY: Double(dropWorld.y)
        ))
    }
}
