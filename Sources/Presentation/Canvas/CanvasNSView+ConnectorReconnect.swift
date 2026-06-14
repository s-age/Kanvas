import AppKit

// MARK: - Connector reconnect (endpoint hit-test / draw / commit)
//
// Re-attaching an existing connector's endpoint by dragging its handle to a different sticky/edge.
// A lone selected connector shows a draggable handle at each endpoint's live edge midpoint; the
// drag previews a line from the fixed end to the cursor, and on mouse-up the dragged end snaps to
// the sticky under the cursor. The attach edge is chosen manually by aim — drop the handle toward
// the edge you want and it attaches there — falling back to the automatic edge nearest the other
// end's midpoint (grow's edge-decision) when the drop lands near the sticky's centre. While the
// drag hovers a candidate target the chosen edge is highlighted live (a bar + ring along that edge —
// see `drawReconnectEdgeHint`) so the aim is discoverable, not invisible. Dropping on empty canvas
// or onto the connector's own other end (a self-loop) snaps back. The begin-press / draft state
// writes live in `CanvasNSView` (same-file `private(set)` mutation); this extension holds the
// read-only hit-test, drawing, and commit logic.

/// Live state for a connector-reconnect gesture: the connector being edited, which end is moving,
/// and the cursor's current world position (the dragged endpoint's free position before it snaps).
struct ConnectorReconnectDraft {
    let connectorID: UUID
    let side: ConnectorEndpointSide
    var currentWorld: CGPoint
}

extension CanvasNSView {

    /// The solely-selected connector, when exactly one item is selected and it is a connector.
    /// Connector and sticky/shape/image selection are mutually exclusive (one `selectedIDs` set), so
    /// this is non-nil exactly when a lone connector is selected — the precondition for showing
    /// endpoint reconnect handles.
    var selectedConnector: ConnectorResponse? {
        guard let id = soleSelectedID else { return nil }
        return connectors.first { $0.id == id }
    }

    /// The selected connector's endpoint handle under `viewPoint`, as (connector id, side), else
    /// `nil`. Each handle sits at the live edge-midpoint of its endpoint sticky — the same point the
    /// connector is drawn from. Reuses the sticky edge handle's `edgeHandleRadius * 2` tolerance.
    func connectorEndpointHandleHit(atView viewPoint: CGPoint) -> (connectorID: UUID, side: ConnectorEndpointSide)? {
        guard let connector = selectedConnector else { return nil }
        if let source = edgeMidpointWorld(stickyID: connector.sourceStickyID, edge: connector.sourceEdge),
           withinHandle(viewPoint, of: source) {
            return (connector.id, .source)
        }
        if let target = edgeMidpointWorld(stickyID: connector.targetStickyID, edge: connector.targetEdge),
           withinHandle(viewPoint, of: target) {
            return (connector.id, .target)
        }
        return nil
    }

    private func withinHandle(_ viewPoint: CGPoint, of world: CGPoint) -> Bool {
        let p = worldToView(world)
        return hypot(viewPoint.x - p.x, viewPoint.y - p.y) <= edgeHandleRadius * 2
    }

    /// Endpoint handles on the selected connector + the in-progress reconnect preview. A lone
    /// selected connector shows a draggable handle at each endpoint's live edge midpoint; while a
    /// reconnect drag is active, the dragged end follows the cursor (a preview line from the fixed
    /// end), mirroring the grow preview. Called from `drawConnectorAffordances`.
    func drawConnectorEndpointAffordances() {
        guard let connector = selectedConnector else { return }
        if let draft = connectorReconnectDraft, draft.connectorID == connector.id {
            drawReconnectPreview(draft, connector: connector)
            return
        }
        if let source = edgeMidpointWorld(stickyID: connector.sourceStickyID, edge: connector.sourceEdge) {
            drawEdgeHandle(at: worldToView(source))
        }
        if let target = edgeMidpointWorld(stickyID: connector.targetStickyID, edge: connector.targetEdge) {
            drawEdgeHandle(at: worldToView(target))
        }
    }

    private func drawReconnectPreview(_ draft: ConnectorReconnectDraft, connector: ConnectorResponse) {
        // Preview a line from the fixed (non-dragged) end to the cursor so the user sees where the
        // dragged end will land.
        let fixedStickyID = draft.side == .source ? connector.targetStickyID : connector.sourceStickyID
        let fixedEdge = draft.side == .source ? connector.targetEdge : connector.sourceEdge
        guard let fixed = edgeMidpointWorld(stickyID: fixedStickyID, edge: fixedEdge) else { return }
        // Discoverability cue: while hovering a candidate target, highlight the edge the drop will
        // attach to (the same decision `commitConnectorReconnect` makes — manual aim, else automatic
        // nearest-to-other fallback). This tells the user *that* drop position selects the edge and
        // *which* edge is currently chosen, instead of leaving the aim affordance invisible.
        drawReconnectEdgeHint(draft, connector: connector, fixedStickyID: fixedStickyID, fixedEdge: fixedEdge)
        let path = NSBezierPath()
        path.move(to: worldToView(fixed))
        path.line(to: worldToView(draft.currentWorld))
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 2
        path.lineCapStyle = .round
        path.stroke()
        drawEdgeHandle(at: worldToView(draft.currentWorld))
    }

    /// Highlights the edge `commitConnectorReconnect` would attach to if the drag were released now,
    /// when the cursor is over a valid target sticky (not empty canvas, not the connector's own other
    /// end). Mirrors the commit's edge decision exactly so the hint never lies. Drawn under the
    /// preview line so the line + cursor handle stay on top.
    private func drawReconnectEdgeHint(_ draft: ConnectorReconnectDraft, connector: ConnectorResponse,
                                       fixedStickyID: UUID, fixedEdge: CanvasEdgeResponse) {
        let dropWorld = draft.currentWorld
        guard case .sticky(let target)? = item(atWorld: dropWorld), target.id != fixedStickyID else {
            return
        }
        let otherMid = edgeMidpointWorld(stickyID: fixedStickyID, edge: fixedEdge) ?? dropWorld
        let targetRect = worldRect(for: .sticky(target))
        let edge = aimedEdge(of: targetRect, dropWorld: dropWorld)
            ?? nearestEdge(of: targetRect, to: otherMid)
        // A short bar along the chosen edge, plus a hollow ring at its midpoint, so the user reads
        // both the edge and its attach point before releasing.
        let targetViewRect = viewRect(for: .sticky(target))
        drawEdgeBar(on: targetViewRect, edge: edge)
        let mid = edgeMidpoint(of: targetViewRect, edge: edge)
        let ring = NSBezierPath(ovalIn: CGRect(x: mid.x - edgeHandleRadius, y: mid.y - edgeHandleRadius,
                                               width: edgeHandleRadius * 2, height: edgeHandleRadius * 2))
        NSColor.controlAccentColor.setStroke()
        ring.lineWidth = 2
        ring.stroke()
    }

    /// Strokes a thick accent bar along `edge` of `viewRect` to mark the reconnect target edge.
    private func drawEdgeBar(on viewRect: CGRect, edge: CanvasEdgeResponse) {
        let path = NSBezierPath()
        switch edge {
        case .top:
            path.move(to: CGPoint(x: viewRect.minX, y: viewRect.minY))
            path.line(to: CGPoint(x: viewRect.maxX, y: viewRect.minY))
        case .bottom:
            path.move(to: CGPoint(x: viewRect.minX, y: viewRect.maxY))
            path.line(to: CGPoint(x: viewRect.maxX, y: viewRect.maxY))
        case .left:
            path.move(to: CGPoint(x: viewRect.minX, y: viewRect.minY))
            path.line(to: CGPoint(x: viewRect.minX, y: viewRect.maxY))
        case .right:
            path.move(to: CGPoint(x: viewRect.maxX, y: viewRect.minY))
            path.line(to: CGPoint(x: viewRect.maxX, y: viewRect.maxY))
        }
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 3
        path.lineCapStyle = .round
        path.stroke()
    }

    /// Dispatches whichever connector gesture is active on mouse-up — a grow (dragging out a new
    /// connector from a sticky edge), a reconnect (dragging a selected connector's endpoint), or a
    /// waypoint (dragging its central deformation handle). At most one draft is ever set per
    /// mouse-down, so this is an either/or.
    func commitActiveConnectorGesture() {
        if let draft = connectorDraft {
            commitConnectorDraft(draft)
        } else if let reconnect = connectorReconnectDraft {
            commitConnectorReconnect(reconnect)
        } else if let waypoint = connectorWaypointDraft {
            commitConnectorWaypoint(waypoint)
        }
    }

    /// Commits a dragged connector endpoint: re-attaches it to the sticky under the cursor. The edge
    /// is chosen **manually by aim** when the drop lands clearly nearer one edge of the target (the
    /// user pointed the handle at the edge they want), and falls back to the **automatic** choice —
    /// the edge nearest the *other* endpoint's midpoint (grow's edge-decision) — when the drop lands
    /// near the sticky's centre (no clear edge intent). This gives explicit per-drag edge control
    /// (surfaced live during the drag by `drawReconnectEdgeHint`, so the aim is discoverable rather
    /// than a separate modal picker), while keeping the centre-drop common case behaving as before.
    /// Snaps back when the drop misses a sticky or would link the connector to its own other end
    /// (a self-loop): no `reconnectConnector` fires, but we still force a redraw so the now-cleared
    /// preview line + cursor handle (last painted in `mouseDragged`) are erased and the connector's
    /// original geometry is repainted — without it the stale preview lingers until an unrelated
    /// redraw. (The grow gesture has no such path: an empty drop there creates a sticky, so it always
    /// mutates and re-pushes.) The domain enforces the self-loop rule too; this guard just avoids a
    /// doomed round-trip.
    func commitConnectorReconnect(_ draft: ConnectorReconnectDraft) {
        guard let connector = connectors.first(where: { $0.id == draft.connectorID }) else { return }
        let dropWorld = draft.currentWorld
        // The endpoint that is NOT moving — its midpoint drives the *automatic* edge fallback.
        let otherStickyID = draft.side == .source ? connector.targetStickyID : connector.sourceStickyID
        let otherEdge = draft.side == .source ? connector.targetEdge : connector.sourceEdge
        let otherMid = edgeMidpointWorld(stickyID: otherStickyID, edge: otherEdge) ?? dropWorld

        guard case .sticky(let target)? = item(atWorld: dropWorld), target.id != otherStickyID else {
            // Empty drop, or would become a self-loop → snap back. No action fires (so no model
            // re-push), so repaint here to erase the lingering preview line + cursor handle.
            needsDisplay = true
            return
        }
        let targetRect = worldRect(for: .sticky(target))
        // Manual aim: when the drop sits in an edge's outer band, honour that edge; otherwise the
        // drop is too central to read intent, so fall back to the automatic nearest-to-other choice.
        let newEdge = aimedEdge(of: targetRect, dropWorld: dropWorld)
            ?? nearestEdge(of: targetRect, to: otherMid)
        actions?.reconnectConnector(ConnectorReconnectGesture(
            connectorID: connector.id, side: draft.side,
            newStickyID: target.id, newEdge: newEdge.rawValue
        ))
    }

    /// The edge the drop is *aimed* at, or `nil` when the drop is too central to read a clear edge
    /// intent. The sticky's interior is split into four triangular quadrants by its diagonals; a drop
    /// in a quadrant aims at that quadrant's edge — but only past an inner dead-zone (a centred
    /// fraction of the rect) where no edge dominates. Dropping in the dead-zone returns `nil` so the
    /// caller keeps the automatic edge choice, preserving the prior centre-drop behaviour.
    ///
    /// Shared with the grow gesture: `commitConnectorDraft` (+Connectors) applies the same aim →
    /// automatic-fallback decision when a grow drop lands on an existing sticky, so reconnect and
    /// grow read edge intent identically. (`internal`, not `private`, for that cross-file reuse.)
    func aimedEdge(of rect: CGRect, dropWorld: CGPoint) -> CanvasEdgeResponse? {
        // Dead-zone: a centred box at `deadZoneFraction` of each side. Inside it, intent is unclear.
        let deadZoneFraction: CGFloat = 0.5
        let dx = dropWorld.x - rect.midX
        let dy = dropWorld.y - rect.midY
        let halfW = rect.width / 2
        let halfH = rect.height / 2
        guard halfW > 0, halfH > 0 else { return nil }
        if abs(dx) <= halfW * deadZoneFraction && abs(dy) <= halfH * deadZoneFraction { return nil }
        // Normalise to the unit square so a non-square sticky's diagonals still split it correctly,
        // then pick the dominant axis. View is flipped (y grows downward): +y is `bottom`, -y `top`.
        // NOTE: this dominant-axis→edge step mirrors `edgeFacing(from:toward:)` (+Connectors) but is
        // deliberately distinct — here deltas are normalised by halfW/halfH (per-aspect-ratio diagonal
        // split) whereas `edgeFacing` compares raw deltas. Keep the flipped-y convention in sync if
        // either changes.
        if abs(dx) / halfW >= abs(dy) / halfH {
            return dx >= 0 ? .right : .left
        }
        return dy >= 0 ? .bottom : .top
    }
}
