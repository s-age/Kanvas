/// Appearance of a connector, editable from the canvas toolbar: the target-end `cap` (line/arrow),
/// the `routing` (straight/elbow/curve), and the stroke colour + width. `strokeWidth` is clamped to
/// `[minStrokeWidth, maxStrokeWidth]` in the initializer (a domain rule). Every domain entry routes
/// through the initializer — `setting…(...)` on write and `BoardSnapshotMapper.toEntities` on load —
/// so an out-of-range JSON width is re-clamped on read. (Persistence is via `ConnectorDTO`, so this
/// type needs no `Codable`.) Mirrors `CanvasShapeStyle`.
struct ConnectorStyle: Sendable, Equatable {
    static let minStrokeWidth: Double = 1
    static let maxStrokeWidth: Double = 40
    static let defaultStrokeWidth: Double = 2

    var cap: ConnectorEndpointCap
    var routing: ConnectorRouting
    /// `nil` = **unset**: the stroke colour was never chosen and no bakeable background existed at
    /// creation, so Presentation resolves it adaptively at draw time (`#333`/`#ddd` by the live
    /// background). A non-nil hex is an explicit pick — including pure `#000000` — honoured verbatim.
    /// This Optional is the end-to-end "unset" representation: it lets an explicitly-chosen black be
    /// distinguished from "never set", which a non-optional sentinel (`#000`) could not.
    var strokeColorHex: String?
    var strokeWidth: Double

    init(
        cap: ConnectorEndpointCap = .arrow,
        routing: ConnectorRouting = .straight,
        strokeColorHex: String? = nil,
        strokeWidth: Double = ConnectorStyle.defaultStrokeWidth
    ) {
        self.cap = cap
        self.routing = routing
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = min(max(strokeWidth, ConnectorStyle.minStrokeWidth), ConnectorStyle.maxStrokeWidth)
    }

    static let `default` = ConnectorStyle()
}
