import AppKit

// MARK: - Coordinate mapping + item geometry
//
// World ⇄ view transform and the centre-anchored rects the canvas draws, hit-tests, drags, and
// resizes against. Kept in a same-folder extension so the main `CanvasNSView` body stays within
// the type/file length budgets. Geometry is `CanvasItem`-based so stickies and shapes share one
// path; the live drag/resize offsets (`draggingID`/`resizingID`) apply identically to both.

extension CanvasNSView {

    func worldToView(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + pan.x, y: point.y * scale + pan.y)
    }

    func viewToWorld(_ point: CGPoint) -> CGPoint {
        CGPoint(x: (point.x - pan.x) / scale, y: (point.y - pan.y) / scale)
    }

    /// World-space rect of a sticky (centre-anchored), with the live drag/resize offset applied.
    func worldRect(for sticky: StickyResponse) -> CGRect {
        worldRect(for: .sticky(sticky))
    }

    /// Centre-anchored world rect of any canvas item, applying the live drag offset (when it is the
    /// dragged item) or the corner-anchored resize preview (when resizing).
    func worldRect(for item: CanvasItem) -> CGRect {
        if item.id == resizingID {
            return resizingWorldRect(for: item)
        }
        // A box shape being reshaped via its corner handle previews the same min/max-clamped rect the
        // sticky/image corner resize uses. (Segment shapes preview via `lineEndpoints`, not a rect.)
        if let drag = activeHandleDrag, drag.shapeID == item.id,
           case .shape(let shape) = item, shape.topology == .box,
           let handle = ShapeRegistry.defaultHandles(for: .box).first {
            return clampedBoxFrame(rawHandleFrame(drag, handle), for: item)
        }
        var centreX = CGFloat(item.centerX)
        var centreY = CGFloat(item.centerY)
        // The drag offset applies to every member of the moving group (just `draggingID` for a
        // single-object drag), so a group drag previews all members following the cursor together.
        if draggingGroupIDs.contains(item.id) {
            centreX += dragWorldDelta.width
            centreY += dragWorldDelta.height
        }
        let w = CGFloat(item.width)
        let h = CGFloat(item.height)
        return CGRect(x: centreX - w / 2, y: centreY - h / 2, width: w, height: h)
    }

    /// World-space rect of the item being resized: the corner opposite the grabbed handle (the
    /// top-left) stays fixed while the grabbed bottom-right corner tracks the cursor. Width and
    /// height clamp to the domain bounds carried on the response, so the preview matches the
    /// committed value (no snap-back). The model anchors by centre, so the new centre is the
    /// resized rect's midpoint — committed together with the size.
    func resizingWorldRect(for item: CanvasItem) -> CGRect {
        let topLeftX = CGFloat(item.centerX) - CGFloat(item.width) / 2
        let topLeftY = CGFloat(item.centerY) - CGFloat(item.height) / 2
        let newW = min(max(CGFloat(item.width) + resizeWorldDelta.width,
                           CGFloat(item.minWidth)), CGFloat(item.maxWidth))
        let newH = min(max(CGFloat(item.height) + resizeWorldDelta.height,
                           CGFloat(item.minHeight)), CGFloat(item.maxHeight))
        // An image keeps its source aspect ratio while resizing, so the preview matches the
        // committed size (`CanvasImageService.resizing` derives height from width + ratio). Drive
        // the size by the width, derive height; if the height clamp bites, fold it back into width.
        if let ratio = item.aspectRatioIfImage, ratio > 0 {
            var lockedW = newW
            var lockedH = min(max(lockedW / ratio, CGFloat(item.minHeight)), CGFloat(item.maxHeight))
            lockedW = min(max(lockedH * ratio, CGFloat(item.minWidth)), CGFloat(item.maxWidth))
            // Re-derive height from the final width, then clamp once more so the back-and-forth
            // never lands a hair outside [minHeight, maxHeight] at extreme values.
            lockedH = min(max(lockedW / ratio, CGFloat(item.minHeight)), CGFloat(item.maxHeight))
            return CGRect(x: topLeftX, y: topLeftY, width: lockedW, height: lockedH)
        }
        return CGRect(x: topLeftX, y: topLeftY, width: newW, height: newH)
    }

    /// Topmost canvas item (sticky or shape) whose hit area contains `worldPoint`. Lines hit-test
    /// by proximity to their segment (their box can be near-flat); everything else by box.
    /// Invariant: `items` is sorted by sortIndex ascending, so the frontmost match is the *last*
    /// one — both this and `draw(_:)` depend on it.
    func item(atWorld worldPoint: CGPoint) -> CanvasItem? {
        items.last { hitTest($0, atWorld: worldPoint) }
    }

    private func hitTest(_ item: CanvasItem, atWorld worldPoint: CGPoint) -> Bool {
        if case .shape(let shape) = item, shape.topology == .segment {
            let (start, end) = lineEndpoints(for: shape)
            // Threshold is a fixed view distance (zoom-independent), converted back to world units.
            return distance(from: worldPoint, toSegment: start, end) <= lineHitTolerance / scale
        }
        return worldRect(for: item).contains(worldPoint)
    }

    // MARK: - Line endpoints

    /// View distance within which a click selects a line, and the radius of an endpoint handle.
    var lineHitTolerance: CGFloat { 6 }

    /// World-space positions of a line's two endpoints (the two opposite corners of its box picked
    /// by `lineRising`). During an endpoint drag the grabbed end follows the cursor and the other
    /// stays fixed; otherwise both derive from the box (which already includes any move offset).
    func lineEndpoints(for shape: ShapeResponse) -> (start: CGPoint, end: CGPoint) {
        if let drag = activeHandleDrag, drag.shapeID == shape.id, shape.topology == .segment {
            // The grabbed endpoint follows the cursor; the opposite endpoint stays fixed. The
            // minimum-length rule is a domain concern enforced on commit by `ShapeService.resizing`.
            let moved = CGPoint(x: drag.grabbedStartWorld.x + resizeWorldDelta.width,
                                y: drag.grabbedStartWorld.y + resizeWorldDelta.height)
            let fixed = drag.handleIndex == 0 ? drag.startEndpoints.end : drag.startEndpoints.start
            return (fixed, moved)
        }
        return endpoints(of: worldRect(for: .shape(shape)), rising: shape.lineRising)
    }

    /// The two diagonal endpoints of `rect`. View is flipped (y grows downward), so "rising"
    /// (bottom-left → top-right) maps to (minX,maxY) → (maxX,minY).
    func endpoints(of rect: CGRect, rising: Bool) -> (start: CGPoint, end: CGPoint) {
        if rising {
            return (CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.minY))
        }
        return (CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.maxY))
    }

    // MARK: - Shape handle drag (corner resize + endpoint drag, unified)

    /// The handle of the selected shape under `viewPoint`, as a ready-to-track drag. `nil` when the
    /// selection is not a shape or no handle is hit. Iterates `ShapeRegistry.defaultHandles(for:)`
    /// so box (one corner) and segment (two endpoints) — and any future topology — share one path.
    func shapeHandleHit(atView viewPoint: CGPoint) -> CanvasShapeHandleDrag? {
        guard let selectedID = soleSelectedID, let shape = shapes.first(where: { $0.id == selectedID }) else {
            return nil
        }
        let worldFrame = worldRect(for: .shape(shape))
        let worldEnds = lineEndpoints(for: shape)
        let viewFrame = viewRect(for: .shape(shape))
        let viewEnds = (start: worldToView(worldEnds.start), end: worldToView(worldEnds.end))
        for (index, handle) in ShapeRegistry.defaultHandles(for: shape.topology).enumerated() {
            let viewPos = handle.position(viewFrame, viewEnds)
            // Box corner uses the square handle's rect; an endpoint uses a round radius.
            let hit = shape.topology == .segment
                ? hypot(viewPoint.x - viewPos.x, viewPoint.y - viewPos.y) <= lineHitTolerance * 2
                : resizeHandleRect(in: viewFrame).contains(viewPoint)
            if hit {
                return CanvasShapeHandleDrag(
                    shapeID: shape.id, handleIndex: index,
                    startWorldFrame: worldFrame, startEndpoints: worldEnds,
                    grabbedStartWorld: handle.position(worldFrame, worldEnds))
            }
        }
        return nil
    }

    /// The raw (unclamped) world frame a box-corner drag requests: the handle closure maps the live
    /// cursor (grabbed corner + drag delta) to a frame with the opposite corner fixed.
    func rawHandleFrame(_ drag: CanvasShapeHandleDrag, _ handle: ShapeHandleSpec) -> CGRect {
        let toWorld = CGPoint(x: drag.grabbedStartWorld.x + resizeWorldDelta.width,
                              y: drag.grabbedStartWorld.y + resizeWorldDelta.height)
        return handle.requestedDrag(toWorld, drag.startWorldFrame, drag.startEndpoints).worldFrame
    }

    /// Clamps a box shape's requested frame to the domain bounds carried on its response, keeping the
    /// fixed (top-left) origin — so the live preview matches the committed value (no snap-back). The
    /// matching `minFilledSide` floor is re-applied by `ShapeService.resizing` on commit.
    func clampedBoxFrame(_ raw: CGRect, for item: CanvasItem) -> CGRect {
        let w = min(max(raw.width, CGFloat(item.minWidth)), CGFloat(item.maxWidth))
        let h = min(max(raw.height, CGFloat(item.minHeight)), CGFloat(item.maxHeight))
        return CGRect(x: raw.minX, y: raw.minY, width: w, height: h)
    }

    /// Shortest distance from `point` to the segment `a`–`b`. Coordinate-space-agnostic (used in
    /// world space for line hit-testing and in view space for connector hit-testing), so it is
    /// `internal` and shared with `CanvasNSView+Connectors`.
    func distance(from point: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x
        let dy = b.y - a.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0.0001 else { return hypot(point.x - a.x, point.y - a.y) }
        var t = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
        t = min(max(t, 0), 1)
        let projX = a.x + t * dx
        let projY = a.y + t * dy
        return hypot(point.x - projX, point.y - projY)
    }
}

/// Live state for dragging one handle of the selected shape — a box corner or a segment endpoint.
/// The grabbed handle tracks the cursor via `resizeWorldDelta`; everything else is captured at
/// mouse-down so the preview/commit math is stable for the gesture's duration.
struct CanvasShapeHandleDrag {
    let shapeID: UUID
    /// Index into `ShapeRegistry.defaultHandles(for:)` for the shape's topology.
    let handleIndex: Int
    /// The shape's world rect at mouse-down (the box corner drag's fixed reference).
    let startWorldFrame: CGRect
    /// The shape's two endpoints at mouse-down (the segment drag's fixed reference).
    let startEndpoints: (start: CGPoint, end: CGPoint)
    /// The grabbed handle's world position at mouse-down; `+ resizeWorldDelta` gives the live point.
    let grabbedStartWorld: CGPoint
}
