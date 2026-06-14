/// On-canvas dimensions of a free-text object (world units). `width`/`height` are clamped to
/// `[min…, max…]` in the initializer (a domain rule). Text wraps to `width`; anything taller than
/// `height` is clipped (hidden) at draw time. Every entry into the domain routes through it —
/// `resizing(...)` on write and `BoardSnapshotMapper.toEntities` on load — so even a hand-edited
/// out-of-range JSON value is re-clamped when read. (Persistence is via `TextDTO`, so this type
/// needs no `Codable`.) A dedicated value object — sibling of `StickySize` / `ShapeSize` — kept
/// independent so the text bounds can be tuned without touching the others.
struct TextSize: Sendable, Equatable {
    static let minWidth: Double = 40
    static let minHeight: Double = 24
    static let maxWidth: Double = 2000
    static let maxHeight: Double = 2000

    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = min(max(width, TextSize.minWidth), TextSize.maxWidth)
        self.height = min(max(height, TextSize.minHeight), TextSize.maxHeight)
    }

    static let `default` = TextSize(width: 200, height: 80)
}
