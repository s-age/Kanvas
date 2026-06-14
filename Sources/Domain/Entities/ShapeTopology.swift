/// How a canvas shape behaves under interaction — independent of its *visual* kind (an open
/// `String` token owned by the Presentation registry). This closed set is what the Domain switches
/// on (resize-clamp rule) and what the canvas uses to choose handles/hit-testing. Adding a closed
/// outline (rectangle/ellipse/triangle/star/…) reuses `.box`; only a genuinely new handle topology
/// needs a new case here (a module-wide compile break, by design — "switch漏れ = compile error").
///
/// The raw value is cross-layer vocabulary shared with the persisted `ShapeDTO.topology` and the
/// Presentation `ShapeTopologyResponse` — never rename a case's raw value or stored shapes
/// stop decoding.
enum ShapeTopology: String, Sendable, CaseIterable, Equatable {
    /// Bounding-box outline with a single bottom-right corner resize handle (filled/stroked path).
    case box
    /// Two-endpoint segment (a line): endpoint handles, segment-proximity hit-testing, no fill.
    case segment

    /// Back-compat: a snapshot or Request predating the `topology` field carries only the visual
    /// `kind`. The only `.segment` shape ever shipped is "line"; everything else is a `.box`.
    ///
    /// - Note: The literal `"line"` is the SOLE place a visual-kind token leaks into Domain
    ///   (back-compat inference only; a future "line" rename must be caught — the existing test
    ///   in `ShapeTopologyTests` pins this mapping to prevent silent breakage).
    static func inferred(fromKind kind: String) -> ShapeTopology {
        kind == "line" ? .segment : .box
    }
}
