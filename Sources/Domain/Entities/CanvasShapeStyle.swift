/// Stroke + fill appearance of a shape, editable from the canvas toolbar. `strokeWidth` is clamped
/// to `[minStrokeWidth, maxStrokeWidth]` in the initializer (a domain rule). `fillColorHex` is
/// `nil` to mean **no fill** (the shape is stroke-only) — distinct from any literal colour. Every
/// domain entry routes through the initializer — `setting…(...)` on write and
/// `BoardSnapshotMapper.toEntities` on load — so an out-of-range JSON width is re-clamped on read.
/// (Persistence is via `ShapeDTO`, so this type needs no `Codable`.)
struct CanvasShapeStyle: Sendable, Equatable {
    static let minStrokeWidth: Double = 1
    static let maxStrokeWidth: Double = 40
    static let defaultStrokeColorHex = "000000"
    static let defaultStrokeWidth: Double = 2
    /// Default fill: a translucent-free, opaque light grey. `nil` would mean "no fill"; a new
    /// shape ships with a visible fill so it reads as a solid object on creation.
    static let defaultFillColorHex: String? = "D9D9D9"

    var strokeColorHex: String
    /// Literal "RRGGBB" hex, or `nil` for **no fill** (stroke-only shape).
    var fillColorHex: String?
    var strokeWidth: Double

    init(strokeColorHex: String = CanvasShapeStyle.defaultStrokeColorHex,
         fillColorHex: String? = CanvasShapeStyle.defaultFillColorHex,
         strokeWidth: Double = CanvasShapeStyle.defaultStrokeWidth) {
        self.strokeColorHex = strokeColorHex
        self.fillColorHex = fillColorHex
        self.strokeWidth = min(max(strokeWidth, CanvasShapeStyle.minStrokeWidth), CanvasShapeStyle.maxStrokeWidth)
    }

    static let `default` = CanvasShapeStyle()
}
