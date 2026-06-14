import AppKit

// MARK: - Gesture commits (mouse-up)
//
// How each in-progress mouse gesture turns into a ViewModel action. Split out of `CanvasNSView` so
// the main file stays within the type/file length budgets. These read live interaction state
// (`draggingID`, `didDrag`, the marquee fields — all `private(set)`) but never write it: the mouse
// handlers in the main file own the writes, these only translate the finished gesture into actions.

extension CanvasNSView {

    /// Commits a shape handle drag (box corner or segment endpoint). Box: snap the min/max-clamped
    /// rect (same as the prior corner resize). Segment: snap both endpoints, then let the handle
    /// closure bound them into the new box and recompute `lineRising`. The domain re-clamps on commit
    /// (`ShapeService.resizing`: `minFilledSide` for box, `minLineLength` for segment).
    func commitShapeHandleDrag(_ drag: CanvasShapeHandleDrag) {
        guard let shape = shapes.first(where: { $0.id == drag.shapeID }),
              let item = items.first(where: { $0.id == drag.shapeID }) else { return }
        let handles = ShapeRegistry.defaultHandles(for: shape.topology)
        guard drag.handleIndex < handles.count else { return }
        let handle = handles[drag.handleIndex]

        if shape.topology == .box {
            let frame = snap(clampedBoxFrame(rawHandleFrame(drag, handle), for: item))
            actions?.resizeShape(id: drag.shapeID, worldFrame: frame, lineRising: nil)
        } else {
            let moved = snap(CGPoint(x: drag.grabbedStartWorld.x + resizeWorldDelta.width,
                                     y: drag.grabbedStartWorld.y + resizeWorldDelta.height))
            let fixedEnds = (start: snap(drag.startEndpoints.start), end: snap(drag.startEndpoints.end))
            let request = handle.requestedDrag(moved, drag.startWorldFrame, fixedEnds)
            actions?.resizeShape(id: drag.shapeID, worldFrame: request.worldFrame,
                                 lineRising: request.rising)
        }
    }

    /// Commits a corner-handle resize of the sticky/image/text with `id`. (Shapes commit via
    /// `commitShapeHandleDrag`, so `resizingID` only ever holds a sticky, image, or text.)
    func commitResize(id: UUID) {
        guard let item = items.first(where: { $0.id == id }) else { return }
        let frame = snap(resizingWorldRect(for: item))
        switch item {
        case .sticky: actions?.setStickyFrame(id: id, worldFrame: frame)
        case .image: actions?.resizeImage(id: id, worldFrame: frame)
        case .text: actions?.setTextFrame(id: id, worldFrame: frame)
        case .shape: break  // unreachable: shapes never set `resizingID`
        }
    }

    /// Commits a plain/group object drag, a marquee selection, or — when the gesture was a tap —
    /// selects what's under the cursor (the dragged item, a connector behind the items, or nothing →
    /// clear selection).
    func commitDragOrTap(downView: CGPoint) {
        if let id = draggingID, let item = items.first(where: { $0.id == id }) {
            if didDrag {
                commitMoveDrag(anchor: item)
            } else {
                // Tap on an item → select it. The highlight follows from the ViewModel round-trip,
                // so the selection has a single source of truth and never diverges from the toolbar.
                selectHit(item)
            }
        } else if didDrag, marqueeViewRect != nil {
            // A marquee drag selects every item it intersected (additive when ⌘ was held).
            actions?.selectRegion(ids: itemIDs(inMarquee: marqueeViewRect ?? .zero),
                                  additive: marqueeAdditive)
        } else if !didDrag, !marqueeAdditive {
            // Plain tap that missed every sticky/shape → select a connector under the cursor (they
            // draw behind items, so they're only reachable here), else clear the selection. A ⌘-tap
            // on empty canvas keeps the current selection (no-op), so it is excluded above.
            if let connector = connector(atWorld: viewToWorld(downView)) {
                actions?.selectConnector(id: connector.id)
            } else {
                actions?.selectSticky(id: nil)
            }
        }
    }

    /// Commits the move of the dragged item — or, when it belongs to a multi-selection, the whole
    /// group by the same snapped delta. The grabbed (anchor) item snaps by its top-left corner — the
    /// same anchor a corner-snapped resize uses, so repeated move/resize keeps it on the grid (a
    /// no-op when snap is off). The model anchors by centre, so the snapped corner converts back to a
    /// centre delta that every group member then shares (preserving their relative layout).
    private func commitMoveDrag(anchor: CanvasItem) {
        let half = CGSize(width: CGFloat(anchor.width) / 2, height: CGFloat(anchor.height) / 2)
        let origin = CGPoint(x: CGFloat(anchor.centerX) + dragWorldDelta.width - half.width,
                             y: CGFloat(anchor.centerY) + dragWorldDelta.height - half.height)
        let snappedOrigin = snap(origin)
        let deltaX = Double(snappedOrigin.x + half.width) - anchor.centerX
        let deltaY = Double(snappedOrigin.y + half.height) - anchor.centerY

        if draggingGroupIDs.count >= 2 {
            let moves = items
                .filter { draggingGroupIDs.contains($0.id) }
                .map { CanvasDragMove(id: $0.id, worldX: $0.centerX + deltaX, worldY: $0.centerY + deltaY) }
            actions?.moveSelected(moves)
            return
        }
        let worldX = anchor.centerX + deltaX
        let worldY = anchor.centerY + deltaY
        switch anchor {
        case .sticky: actions?.moveSticky(id: anchor.id, worldX: worldX, worldY: worldY)
        case .shape: actions?.moveShape(id: anchor.id, worldX: worldX, worldY: worldY)
        case .image: actions?.moveImage(id: anchor.id, worldX: worldX, worldY: worldY)
        case .text: actions?.moveText(id: anchor.id, worldX: worldX, worldY: worldY)
        }
    }
}
