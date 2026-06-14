import AppKit

// MARK: - Image drawing
//
// Images render their decoded pixels into the item's box. Like shapes, they share the canvas
// transform, hit-testing, drag, and resize with stickies (via `CanvasItem`); only the paint
// differs. Pixels are fetched lazily by `assetID` (the board snapshot carries only a reference),
// decoded once into `imageCache`, and a placeholder is drawn until the bytes arrive.

extension CanvasNSView {

    /// Consecutive transient fetch failures tolerated for one asset before it is treated as terminal.
    /// The genuine transient (an external atomic replace) clears in ~1 redraw, well under this, so the
    /// cap only catches a fault that looked transient but persists (an unreadable sidecar).
    static let transientImageLoadRetryLimit = 3

    func draw(image: ImageResponse) {
        let rect = viewRect(for: .image(image))

        if let cached = cachedImage(for: image.assetID) {
            // `respectFlipped` keeps the bitmap upright in this flipped view; clip to a subtle
            // rounded rect so the corners match the rest of the canvas's visual language.
            NSGraphicsContext.current?.saveGraphicsState()
            let clip = NSBezierPath(roundedRect: rect, xRadius: 4 * scale, yRadius: 4 * scale)
            clip.addClip()
            cached.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                        respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.current?.restoreGraphicsState()
        } else {
            drawImagePlaceholder(in: rect)
        }

        // Selection affordance: accent bounding box (any selection) + corner resize handle (only a
        // lone selection — a multi-selection can't resize). Shared look with stickies/shapes.
        if isSelected(image.id) {
            let selectionBox = NSBezierPath(rect: rect)
            NSColor.controlAccentColor.setStroke()
            selectionBox.lineWidth = 1
            selectionBox.stroke()
            if isSoleSelection(image.id) { drawResizeHandle(in: rect) }
        }
    }

    /// A neutral box shown while an image's bytes are still loading (or failed to decode), so the
    /// item is visible, selectable, and draggable before its pixels arrive.
    private func drawImagePlaceholder(in rect: CGRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 4 * scale, yRadius: 4 * scale)
        NSColor.windowBackgroundColor.setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    /// The decoded image for `assetID`, or `nil` while it loads (or permanently, if it failed). On
    /// a cache miss it kicks off a one-shot async fetch (deduped via `pendingImageLoads`); when the
    /// bytes arrive they are decoded, cached, and the canvas is redrawn. An asset that already
    /// failed *terminally* (`failedImageLoads`) is not retried — otherwise every redraw would re-hit
    /// the disk. A *transient* failure is deliberately left out of that set so it retries.
    private func cachedImage(for assetID: UUID) -> NSImage? {
        if let cached = imageCache[assetID] { return cached }
        loadImageIfNeeded(assetID: assetID)
        return nil
    }

    /// Kicks off the one-shot async fetch for `assetID` unless it is already in-flight or has been
    /// negative-cached. Returns the spawned `Task` (or `nil` when the guard short-circuits and no
    /// fetch starts) so a test can deterministically await the fetch + its state mutations; the
    /// production caller (`cachedImage`) fire-and-forgets it via `@discardableResult`.
    @discardableResult
    func loadImageIfNeeded(assetID: UUID) -> Task<Void, Never>? {
        guard !pendingImageLoads.contains(assetID), !failedImageLoads.contains(assetID) else { return nil }
        pendingImageLoads.insert(assetID)
        return Task { [weak self] in
            // No handler yet (view detached mid-fetch) → not terminal: drop the in-flight marker so a
            // later redraw retries once the coordinator is reattached.
            guard let actions = self?.actions else { self?.pendingImageLoads.remove(assetID); return }
            let outcome = await actions.imageData(assetID: assetID)
            guard let self else { return }
            self.pendingImageLoads.remove(assetID)
            switch outcome {
            case .loaded(let data):
                self.transientImageLoadAttempts[assetID] = nil
                guard let decoded = NSImage(data: data) else {
                    // Bytes present but undecodable → terminal. Negative-cache it and report why, so
                    // the corrupt-sidecar reason is not lost (only the canvas can see the decode fail).
                    self.failedImageLoads.insert(assetID)
                    actions.reportImageLoadFailure(assetID: assetID, reason: .undecodableData)
                    return
                }
                self.imageCache[assetID] = decoded
                self.needsDisplay = true
            case .unavailable:
                // Genuinely missing asset → terminal. Negative-cache so it is attempted exactly once,
                // and surface the reason behind the otherwise-silent placeholder.
                self.transientImageLoadAttempts[assetID] = nil
                self.failedImageLoads.insert(assetID)
                actions.reportImageLoadFailure(assetID: assetID, reason: .missingAsset)
            case .transientFailure:
                // Fetch error / cancellation — NOT terminal on its own; left out of `failedImageLoads`
                // so the next redraw retries and a passing transient resolves itself. But a fault that
                // keeps recurring is really persistent (an unreadable sidecar) — without a cap it would
                // re-fetch every redraw forever, and silently (transients aren't reported). Promote to
                // terminal after the retry limit: negative-cache + report once.
                let attempts = (self.transientImageLoadAttempts[assetID] ?? 0) + 1
                if attempts >= Self.transientImageLoadRetryLimit {
                    self.transientImageLoadAttempts[assetID] = nil
                    self.failedImageLoads.insert(assetID)
                    actions.reportImageLoadFailure(assetID: assetID, reason: .unreadable)
                } else {
                    self.transientImageLoadAttempts[assetID] = attempts
                }
            }
        }
    }
}
