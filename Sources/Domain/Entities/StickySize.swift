/// On-canvas dimensions of a sticky (world units). `width`/`height` are clamped to
/// `[min…, max…]` in the initializer (a domain rule). Every entry into the domain routes
/// through it — `settingFrame(...)` on write, and `BoardSnapshotMapper.toEntities` reconstructs
/// `StickySize(width:height:)` on load — so even a hand-edited out-of-range JSON value is
/// re-clamped when read. (Persistence is via `StickyDTO`, so this type needs no `Codable`.)
struct StickySize: Sendable, Equatable {
    static let minWidth: Double = 80
    static let minHeight: Double = 60
    static let maxWidth: Double = 2000
    static let maxHeight: Double = 2000

    var width: Double
    var height: Double

    init(width: Double, height: Double) {
        self.width = min(max(width, StickySize.minWidth), StickySize.maxWidth)
        self.height = min(max(height, StickySize.minHeight), StickySize.maxHeight)
    }

    static let `default` = StickySize(width: 200, height: 150)
}
