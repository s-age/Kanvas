import AppKit

// MARK: - Free-text drawing
//
// A free-text object draws plain text with no background and no border. Text wraps to the box width
// and anything taller than the box height is clipped (hidden) — the box is a hard visual frame even
// though it is never stroked. Texts share the canvas transform, hit-testing, drag, and corner resize
// with stickies/images (via `CanvasItem`); only the paint differs. The overlaid editor draws the
// text while a text object is being edited, so the drawn text is suppressed then (like a sticky).

extension CanvasNSView {

    func draw(text: TextResponse) {
        let rect = viewRect(for: .text(text))

        // The overlaid editor renders the text while editing — don't draw under it.
        if text.id != editingID, !text.content.isEmpty {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping  // wrap to the box width
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: text.fontSize * scale),
                .foregroundColor: NSColor(hex: text.textColorHex),
                .paragraphStyle: paragraph,
            ]
            // Inset the text by the same `4 * scale` the editor frame uses in `beginEditingText`, so
            // the glyphs sit in the same place editing vs. committed — no visual jump on commit.
            let textRect = rect.insetBy(dx: 4 * scale, dy: 4 * scale)
            // Clip to the box so overflow past `height` is hidden (the ticket's clip rule). The save/
            // restore keeps the clip local to this one text object.
            NSGraphicsContext.current?.saveGraphicsState()
            NSBezierPath(rect: rect).addClip()
            (text.content as NSString).draw(in: textRect, withAttributes: attributes)
            NSGraphicsContext.current?.restoreGraphicsState()
        }

        // Selection affordance: an accent bounding box (so an otherwise border-less object is
        // visibly selected) plus a corner resize handle when it is the lone selection.
        if isSelected(text.id) {
            let selectionBox = NSBezierPath(rect: rect)
            NSColor.controlAccentColor.setStroke()
            selectionBox.lineWidth = 1
            selectionBox.stroke()
            if isSoleSelection(text.id) { drawResizeHandle(in: rect) }
        }
    }
}
