import AppKit

// MARK: - Shape drawing
//
// Shapes (rectangle / ellipse / line) render their own stroke + optional fill. They share the
// canvas transform, hit-testing, drag, and resize with stickies (via `CanvasItem`); only the paint
// differs. A `nil` fill means stroke-only ("no fill").

extension CanvasNSView {

    func draw(shape: ShapeResponse) {
        let strokeColor = NSColor(hex: shape.strokeColorHex)
        let lineWidth = max(CGFloat(shape.strokeWidth) * scale, 0.5)

        // A segment is two endpoints with its own selection affordance (an endpoint handle on each
        // end); it has no bounding-box border or corner handle.
        if shape.topology == .segment {
            drawSegment(shape: shape, strokeColor: strokeColor, lineWidth: lineWidth)
            return
        }

        let rect = viewRect(for: .shape(shape))
        // Registry-driven outline. Only use the registry path when the definition exists AND its
        // topology is .box — a known-but-segment definition (e.g. "line") paired onto a box-topology
        // shape would produce an empty path and silently vanish. Unknown kind → fall back to a
        // rectangle so the shape still renders.
        let def = ShapeRegistry.definition(forKind: shape.kind)
        let path = (def?.topology == .box ? def?.path(rect) : nil) ?? NSBezierPath(rect: rect)
        drawClosed(path, shape: shape, strokeColor: strokeColor, lineWidth: lineWidth)

        // Selection affordance for filled shapes: accent bounding box (any selection) + corner resize
        // handle (only a lone selection — a multi-selection can't resize).
        if isSelected(shape.id) {
            let selectionBox = NSBezierPath(rect: rect)
            NSColor.controlAccentColor.setStroke()
            selectionBox.lineWidth = 1
            selectionBox.stroke()
            if isSoleSelection(shape.id) { drawResizeHandle(in: rect) }
        }
    }

    /// Fills (when the shape has a fill colour) then strokes a closed path (rectangle / ellipse).
    private func drawClosed(_ path: NSBezierPath, shape: ShapeResponse,
                            strokeColor: NSColor, lineWidth: CGFloat) {
        if let fillHex = shape.fillColorHex {
            NSColor(hex: fillHex).setFill()
            path.fill()
        }
        strokeColor.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }

    /// Draws a segment between its two endpoints. When selected, each endpoint carries a
    /// draggable handle. Fill does not apply to a segment.
    private func drawSegment(shape: ShapeResponse, strokeColor: NSColor, lineWidth: CGFloat) {
        let (startWorld, endWorld) = lineEndpoints(for: shape)
        let start = worldToView(startWorld)
        let end = worldToView(endWorld)

        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        // A segment has no bounding box, so selection shows by tinting the stroke accent (and, for a
        // lone selection, the draggable endpoint handles). A multi-selected segment gets the accent
        // tint but no handles (no resize on a multi-selection).
        let selected = isSelected(shape.id)
        (selected ? NSColor.controlAccentColor : strokeColor).setStroke()
        path.lineWidth = selected ? lineWidth + 1 : lineWidth
        path.lineCapStyle = .round
        path.stroke()

        if isSoleSelection(shape.id) {
            drawEndpointHandle(at: start)
            drawEndpointHandle(at: end)
        }
    }

    /// A round drag handle centred on a line endpoint (same look as the corner resize handle).
    private func drawEndpointHandle(at point: CGPoint) {
        let radius = resizeHandleSize / 2
        let rect = CGRect(x: point.x - radius, y: point.y - radius,
                          width: resizeHandleSize, height: resizeHandleSize)
        let path = NSBezierPath(ovalIn: rect)
        NSColor.controlAccentColor.setFill()
        path.fill()
        NSColor.windowBackgroundColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }
}
