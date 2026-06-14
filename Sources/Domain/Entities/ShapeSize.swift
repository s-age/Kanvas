/// On-canvas dimensions of a shape (world units). `width`/`height` are clamped to `[min…, max…]`
/// in the initializer (a domain rule). Mirrors `StickySize`, but allows a much smaller minimum so
/// a `line` (drawn as its bounding-box diagonal) can be made thin. Every entry into the domain
/// routes through it — `resizing(...)` on write and `BoardSnapshotMapper.toEntities` on load — so
/// an out-of-range JSON value is re-clamped when read. (Persistence is via `ShapeDTO`, so this
/// type needs no `Codable`.)
struct ShapeSize: Sendable, Equatable {
    // Floor is 0 so a line dragged to horizontal/vertical can have a genuinely flat bounding box
    // (one side near zero). Filled shapes (rectangle / ellipse) keep a larger usable minimum,
    // enforced kind-awarely in `ShapeService.resizing` via `minFilledSide` — `ShapeSize` itself
    // does not know the kind, so the floor here must accommodate the smallest case (a line).
    static let minWidth: Double = 0
    static let minHeight: Double = 0
    static let maxWidth: Double = 4000
    static let maxHeight: Double = 4000
    /// Minimum side a *filled* shape (rectangle / ellipse) may shrink to — keeps it visible and its
    /// resize handle grabbable. Applied in `ShapeService.resizing` for non-line kinds.
    static let minFilledSide: Double = 8
    /// Minimum length (box diagonal) a line may shrink to — keeps it visible and its endpoint
    /// handles grabbable. Applied in `ShapeService.resizing` for the line kind.
    static let minLineLength: Double = 8

    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = min(max(width, ShapeSize.minWidth), ShapeSize.maxWidth)
        self.height = min(max(height, ShapeSize.minHeight), ShapeSize.maxHeight)
    }

    static let `default` = ShapeSize(width: 160, height: 120)
}
