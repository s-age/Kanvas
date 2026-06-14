/// On-canvas dimensions of an image (world units). `width`/`height` are clamped to `[min…, max…]`
/// in the initializer (a domain rule). Mirrors `StickySize`/`ShapeSize`. Every entry into the
/// domain routes through it — `resizing(...)` on write and `BoardSnapshotMapper.toEntities` on
/// load — so an out-of-range JSON value is re-clamped when read. (Persistence is via `ImageDTO`,
/// so this type needs no `Codable`.)
///
/// Aspect-ratio preservation is **not** enforced here (`ImageSize` does not know the image's
/// natural ratio); `CanvasImageService.resizing` derives the height from the width and the
/// `CanvasImage.aspectRatio` so a resized image never distorts.
struct ImageSize: Sendable, Equatable {
    static let minWidth: Double = 32
    static let minHeight: Double = 32
    static let maxWidth: Double = 4000
    static let maxHeight: Double = 4000
    /// Largest side a freshly-pasted/dropped image is fit into, preserving aspect ratio, so a
    /// full-resolution screenshot does not land larger than the viewport. Applied in
    /// `CanvasImageService.fittedSize`.
    static let defaultMaxSide: Double = 360

    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = min(max(width, ImageSize.minWidth), ImageSize.maxWidth)
        self.height = min(max(height, ImageSize.minHeight), ImageSize.maxHeight)
    }
}
