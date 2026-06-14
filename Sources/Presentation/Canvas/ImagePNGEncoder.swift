import AppKit

/// PNG-encodes an `NSImage`, downscaling any source whose long side exceeds `maxStoredImagePixelSide`
/// so a huge screenshot never lands as a multi-MB asset or a giant decoded bitmap. Shared by both
/// AppKit carve-outs: the canvas (drop / ⌘V image-on-canvas, `CanvasNSView+DragDrop` / `+Keyboard`)
/// and the Markdown editor (inline image drop, `Views/Markdown/`). Lives in the `Canvas/` carve-out
/// folder so it may `import AppKit`; the Markdown carve-out references it across the same module.
///
/// The display size derives elsewhere (canvas: `fittedImage`; Markdown: editor-width fit), so this
/// returns only the encoded bytes plus the (possibly capped) pixel dimensions.
enum ImagePNGEncoder {
    /// Largest pixel side a pasted/dropped image is stored at (long side). Keeps asset files and the
    /// decoded-image caches bounded; neither surface displays beyond a few hundred points.
    static let maxStoredImagePixelSide = 2048

    /// Encodes `image` to PNG, returning the bytes plus the (possibly capped) pixel dimensions, or
    /// `nil` when it cannot rasterize. A source larger than `maxStoredImagePixelSide` on its long
    /// side is downscaled first (aspect-preserving, high-quality interpolation).
    static func pngPayload(from image: NSImage) -> (data: Data, width: Double, height: Double)? {
        guard let tiff = image.tiffRepresentation, let source = NSBitmapImageRep(data: tiff) else {
            return nil
        }
        let rep = downscaledIfNeeded(source)
        guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
        return (png, Double(rep.pixelsWide), Double(rep.pixelsHigh))
    }

    /// Returns `rep` unchanged when its long side is within the cap, else a downscaled copy
    /// preserving aspect ratio (high-quality interpolation). Falls back to the original on failure.
    private static func downscaledIfNeeded(_ rep: NSBitmapImageRep) -> NSBitmapImageRep {
        let cap = maxStoredImagePixelSide
        let longSide = max(rep.pixelsWide, rep.pixelsHigh)
        guard longSide > cap else { return rep }
        let scale = Double(cap) / Double(longSide)
        let targetW = max(1, Int((Double(rep.pixelsWide) * scale).rounded()))
        let targetH = max(1, Int((Double(rep.pixelsHigh) * scale).rounded()))
        guard let target = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: targetW, pixelsHigh: targetH,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return rep }
        target.size = NSSize(width: targetW, height: targetH)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: target)
        NSGraphicsContext.current?.imageInterpolation = .high
        rep.draw(in: NSRect(x: 0, y: 0, width: targetW, height: targetH))
        NSGraphicsContext.restoreGraphicsState()
        return target
    }
}
