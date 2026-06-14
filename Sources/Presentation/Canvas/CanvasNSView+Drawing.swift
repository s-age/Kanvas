import AppKit

// MARK: - Drawing

extension CanvasNSView {

    // Pan/zoom/drag redraw the whole view each event. Items and connectors outside `dirtyRect` are
    // culled (viewport culling) so a large board only pays for what is on screen; text attributes
    // are still rebuilt per visible sticky per draw (cheap once off-screen layout is skipped).
    override func draw(_ dirtyRect: CGRect) {
        canvasBackgroundColor.setFill()
        dirtyRect.fill()

        // Connectors render first so they tuck behind every sticky/shape (they take no part in the
        // `items` z-order). Off-screen connectors are culled inside.
        drawConnectors(in: dirtyRect)

        // Back → front — relies on the sortIndex-ascending invariant of `items`. Stickies and
        // shapes interleave by their shared sortIndex, so the merged order is the draw order. Items
        // whose view rect misses `dirtyRect` are skipped — the bounding box fully contains a line's
        // segment too, so culling by it never drops a visible line. The 1pt expansion both adds a
        // boundary margin and gives a perfectly vertical/horizontal line (a zero-area box, which
        // `intersects` treats as empty) a non-empty rect so it is not wrongly culled.
        for item in items where viewRect(for: item).insetBy(dx: -1, dy: -1).intersects(dirtyRect) {
            switch item {
            case .sticky(let sticky): draw(sticky: sticky)
            case .shape(let shape): draw(shape: shape)
            case .image(let image): draw(image: image)
            case .text(let text): draw(text: text)
            }
        }

        // Edge handles on the selected sticky + the in-progress grow preview sit on top of items.
        drawConnectorAffordances()

        // The rubber-band marquee (if a region drag is in progress) sits on top of everything.
        drawMarquee()
    }

    /// Draws the in-progress marquee: a translucent accent fill under a dashed accent border. No-op
    /// when no region drag is active.
    private func drawMarquee() {
        guard let rect = marqueeViewRect else { return }
        let path = NSBezierPath(rect: rect)
        NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
        path.fill()
        NSColor.controlAccentColor.setStroke()
        path.lineWidth = 1
        let dash: [CGFloat] = [4, 3]
        path.setLineDash(dash, count: dash.count, phase: 0)
        path.stroke()
    }

    /// View-space rect of a sticky (centre-anchored, drag offset + zoom applied).
    func viewRect(for sticky: StickyResponse) -> CGRect {
        viewRect(fromWorld: worldRect(for: sticky))
    }

    /// View-space rect of any canvas item (sticky or shape).
    func viewRect(for item: CanvasItem) -> CGRect {
        viewRect(fromWorld: worldRect(for: item))
    }

    private func viewRect(fromWorld rectWorld: CGRect) -> CGRect {
        let origin = worldToView(CGPoint(x: rectWorld.minX, y: rectWorld.minY))
        return CGRect(
            x: origin.x,
            y: origin.y,
            width: rectWorld.width * scale,
            height: rectWorld.height * scale
        )
    }

    private func draw(sticky: StickyResponse) {
        let rect = viewRect(for: sticky)
        let radius = 8 * scale
        let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

        let fill = tintColor(for: sticky).withAlphaComponent(tintFraction(for: sticky))
        fill.setFill()
        path.fill()

        if isSelected(sticky.id) {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 2
        } else {
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        // The overlaid editor renders the text while editing — don't draw under it.
        if sticky.id != editingID {
            drawText(for: sticky, in: rect)
        }

        // Assigned labels render as coloured pills along the bottom edge.
        if !sticky.labels.isEmpty {
            drawLabels(for: sticky, in: rect)
        }

        // A lone selected sticky carries a corner handle for resizing (multi-selection can't resize).
        if isSoleSelection(sticky.id) {
            drawResizeHandle(in: rect)
        }

        // The label icon surfaces on hover or a lone selection so labels can be managed.
        if isSoleSelection(sticky.id) || sticky.id == hoverID {
            drawLabelIcon(in: rect)
        }
    }

    /// View-space rect of the resize handle, centred on an item's bottom-right corner.
    func resizeHandleRect(in viewRect: CGRect) -> CGRect {
        CGRect(
            x: viewRect.maxX - resizeHandleSize / 2,
            y: viewRect.maxY - resizeHandleSize / 2,
            width: resizeHandleSize,
            height: resizeHandleSize
        )
    }

    func drawResizeHandle(in rect: CGRect) {
        let path = NSBezierPath(ovalIn: resizeHandleRect(in: rect))
        NSColor.controlAccentColor.setFill()
        path.fill()
        NSColor.windowBackgroundColor.setStroke()
        path.lineWidth = 1.5
        path.stroke()
    }

    /// The selected sticky/image id when `viewPoint` lands on its corner resize handle. Shapes are
    /// excluded — every shape (box corner or segment endpoints) resizes via `shapeHandleHit`.
    func resizeHandleItemID(atView viewPoint: CGPoint) -> UUID? {
        guard let selectedID = soleSelectedID, let item = items.first(where: { $0.id == selectedID }) else {
            return nil
        }
        if case .shape = item { return nil }
        return resizeHandleRect(in: viewRect(for: item)).contains(viewPoint) ? selectedID : nil
    }

    private func drawText(for sticky: StickyResponse, in rect: CGRect) {
        let padding = 8 * scale
        var textRect = rect.insetBy(dx: padding, dy: padding)
        // Reserve the bottom strip for the label pills so they don't overlap the text.
        if !sticky.labels.isEmpty {
            textRect.size.height = max(0, textRect.height - (pillHeight + padding))
        }
        guard textRect.width > 0, textRect.height > 0 else { return }

        var text = ""
        if sticky.isTask, let title = sticky.linkedCardTitle {
            text = "☑︎ \(title)\n"
        }
        text += sticky.content

        // Font size + colour are per-sticky (editable from the toolbar); paragraph style is
        // constant (hoisted). Font is additionally scaled by the zoom factor.
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: sticky.fontSize * scale),
            .foregroundColor: effectiveTextColor(for: sticky),
            .paragraphStyle: textParagraphStyle,
        ]
        (text as NSString).draw(in: textRect, withAttributes: attributes)
    }
}

// MARK: - Labels

/// Cache key for a measured label-pill text size: the label name and the pill font size. Two pills
/// with the same name and zoom-derived font size measure identically, so they share one entry.
struct PillTextSizeKey: Hashable {
    let name: String
    let fontSize: CGFloat
}

extension CanvasNSView {

    /// Side of the square label icon, in view points (zoom-independent, like the resize handle).
    var labelIconSize: CGFloat { 16 }
    /// Height of a label pill, scaled with zoom but clamped to a readable range.
    var pillHeight: CGFloat { min(max(14 * scale, 12), 20) }

    /// View-space rect of the label icon, in the sticky's top-right corner.
    private func labelIconRect(in viewRect: CGRect) -> CGRect {
        CGRect(
            x: viewRect.maxX - labelIconSize - 4,
            y: viewRect.minY + 4,
            width: labelIconSize,
            height: labelIconSize
        )
    }

    /// The hovered/selected sticky whose label icon `viewPoint` lands on, else `nil`. Only a
    /// sticky currently showing the icon (selected or hovered) is hittable.
    func labelIconStickyID(atView viewPoint: CGPoint) -> UUID? {
        for sticky in stickies.reversed() where isSoleSelection(sticky.id) || sticky.id == hoverID {
            if labelIconRect(in: viewRect(for: sticky)).contains(viewPoint) { return sticky.id }
        }
        return nil
    }

    private func drawLabelIcon(in rect: CGRect) {
        let iconRect = labelIconRect(in: rect)
        let bg = NSBezierPath(roundedRect: iconRect, xRadius: 4, yRadius: 4)
        NSColor.windowBackgroundColor.withAlphaComponent(0.9).setFill()
        bg.fill()
        NSColor.separatorColor.setStroke()
        bg.lineWidth = 0.5
        bg.stroke()

        guard let image = labelIconImage() else { return }
        let size = image.size
        let drawRect = CGRect(
            x: iconRect.midX - size.width / 2,
            y: iconRect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
        // respectFlipped keeps the glyph upright in this flipped view.
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
    }

    /// The tag glyph for the label icon, built once and cached on `cachedLabelIconImage`. It depends
    /// only on the constant `labelIconSize` and the accent colour, so rebuilding it per draw (it
    /// renders for the hovered/selected sticky every frame during a drag) was pure waste. The cache
    /// is cleared on an effective-appearance change (`viewDidChangeEffectiveAppearance`).
    private func labelIconImage() -> NSImage? {
        if let cachedLabelIconImage { return cachedLabelIconImage }
        let config = NSImage.SymbolConfiguration(pointSize: labelIconSize * 0.62, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        let image = NSImage(systemSymbolName: "tag.fill", accessibilityDescription: "Label")?
            .withSymbolConfiguration(config)
        cachedLabelIconImage = image
        return image
    }

    /// Lays out the assigned labels as coloured pills along the bottom edge, left to right,
    /// stopping when the row runs out of horizontal room (leaving the resize-handle corner clear).
    private func drawLabels(for sticky: StickyResponse, in rect: CGRect) {
        let padding = 8 * scale
        let spacing = 4 * scale
        let height = pillHeight
        let y = rect.maxY - padding - height
        guard y > rect.minY else { return }
        var x = rect.minX + padding
        let maxX = rect.maxX - padding - resizeHandleSize

        // The font depends only on the pill height (a zoom function), not the individual label — so
        // build (or fetch the cached) font once per draw and reuse across every pill, rather than
        // allocating an `NSFont.systemFont(...)` per visible pill per draw.
        let fontSize = max(height * 0.6, 7)
        let font = pillFont(ofSize: fontSize)

        for label in sticky.labels {
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: readableTextColor(onHex: label.colorHex),
            ]
            // Measured the same way as before (`size(withAttributes:)`), but memoised by
            // (name, fontSize) so the same string isn't re-measured every redraw. The measurement is
            // font-only (`.foregroundColor` doesn't affect glyph metrics), so the keyless-of-colour
            // cache returns the identical size the per-draw call produced.
            let textSize = pillTextSize(for: label.name, fontSize: fontSize, font: font)
            let pillWidth = textSize.width + height  // ~half-height padding each side
            // Stop once a pill would overflow (but always draw at least the first one).
            if x + pillWidth > maxX, x > rect.minX + padding { break }

            let pillRect = CGRect(x: x, y: y, width: min(pillWidth, max(maxX - x, height)), height: height)
            let pillPath = NSBezierPath(roundedRect: pillRect, xRadius: height / 2, yRadius: height / 2)
            NSColor(hex: label.colorHex).setFill()
            pillPath.fill()

            let inset = (height - textSize.height) / 2
            let textRect = pillRect.insetBy(dx: height * 0.4, dy: inset)
            if textRect.width > 0 {
                (label.name as NSString).draw(in: textRect, withAttributes: attributes)
            }
            x += pillWidth + spacing
        }
    }

    /// The label-pill font for `fontSize`, cached on the view so it is rebuilt only when the
    /// zoom-derived size changes — not per pill per draw. Main-thread-only (draw), so no lock.
    ///
    /// A single draw pass uses one zoom-derived `fontSize` for every pill, so whenever it changes
    /// the whole `pillTextSizeCache` is keyed at the prior (now unreachable) size and would never be
    /// hit again. Drop it here, on the size transition: this bounds the text-size cache to the
    /// labels measured at the *current* size (the name-based prune in `update(_:)` only bounds the
    /// name axis, never the zoom axis). A drag holds zoom steady, so the size doesn't change mid-drag
    /// and steady-state hit rate is preserved; only an actual pinch-zoom step pays the re-measure.
    private func pillFont(ofSize fontSize: CGFloat) -> NSFont {
        if let cachedPillFont, cachedPillFontSize == fontSize { return cachedPillFont }
        let font = NSFont.systemFont(ofSize: fontSize, weight: .medium)
        cachedPillFont = font
        cachedPillFontSize = fontSize
        pillTextSizeCache.removeAll(keepingCapacity: true)
        return font
    }

    /// Measured pill-text size for `name` at `fontSize`, memoised by `(name, fontSize)` so the
    /// `size(withAttributes:)` text-layout call isn't repeated for the same string every draw.
    /// Only the font drives glyph metrics (colour doesn't), so the size is identical to the prior
    /// per-draw call. Main-thread-only (draw), so the cache needs no lock.
    private func pillTextSize(for name: String, fontSize: CGFloat, font: NSFont) -> CGSize {
        let key = PillTextSizeKey(name: name, fontSize: fontSize)
        if let cached = pillTextSizeCache[key] { return cached }
        let size = (name as NSString).size(withAttributes: [.font: font])
        pillTextSizeCache[key] = size
        return size
    }

    /// Black-ish or white text, whichever reads better on `hex` (luminance threshold), for label
    /// pills drawn opaque over the sticky. Uses the shared `perceptualLuminance(of:)` (canonical
    /// `0.299/0.587/0.114` weights) with the `0.6` threshold matching
    /// `ContrastColor.readableHex(onBackground:)`. Note: pills go full `.white` on dark, whereas
    /// sticky *text* uses the softer `#ddd`; keep that divergence intentional if you touch one.
    private func readableTextColor(onHex hex: String) -> NSColor {
        perceptualLuminance(of: NSColor(hex: hex)) > 0.6 ? NSColor(hex: "333333") : .white
    }
}
