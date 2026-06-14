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
    func commitConnectorWaypoint(_ draft: ConnectorWaypointDraft) {
        guard let connector = connectors.first(where: { $0.id == draft.connectorID }),
              let base = connectorEndpointsMidpointWorld(connector) else {
            needsDisplay = true
            return
        }
        let offsetX = Double(draft.currentWorld.x - base.x)
        let offsetY = Double(draft.currentWorld.y - base.y)
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
}
