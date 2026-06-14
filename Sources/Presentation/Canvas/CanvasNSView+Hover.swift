import AppKit

// MARK: - Hover tracking (label-icon affordance)
//
// The label icon surfaces on hover as well as on selection, so the canvas tracks which sticky
// is under the cursor. This is view-local state driving only the affordance overlay; it is not
// routed through the ViewModel.

extension CanvasNSView {

    /// A single `.inVisibleRect` tracking area for hover detection — auto-sized to the view, so
    /// no manual rect bookkeeping on resize/scroll. Rebuilt by AppKit via `updateTrackingAreas`.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseMoved(with event: NSEvent) {
        let world = viewToWorld(convert(event.locationInWindow, from: nil))
        // Only the topmost item shows a hover affordance, and only when it is a sticky (the label
        // icon is sticky-only). A shape covering a sticky suppresses the sticky's icon.
        updateHover(to: item(atWorld: world)?.stickyValue?.id)
    }

    override func mouseExited(with event: NSEvent) {
        updateHover(to: nil)
    }

    private func updateHover(to id: UUID?) {
        guard hoverID != id else { return }
        hoverID = id
        needsDisplay = true  // show / hide the label icon on the affected stickies
    }
}
