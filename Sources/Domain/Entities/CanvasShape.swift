import Foundation

/// A drawable shape on a card's canvas. Mirrors `Sticky` as a resizable canvas object, but carries
/// stroke/fill styling instead of text. Shares the canvas `sortIndex` z-order space with stickies
/// (see `BoardState.nextFrontCanvasIndex`), so a shape can sit in front of or behind a sticky.
struct CanvasShape: Sendable, Identifiable, Equatable {
    let id: UUID
    var cardID: Card.ID
    /// Open visual token (e.g. "rectangle" / "ellipse" / "line" / "triangle"). The Domain never
    /// switches on this — only the Presentation registry interprets it for drawing/palette.
    var kind: String
    /// Behaviour class — the closed set the Domain switches on (resize clamp). Persisted so the
    /// rule never needs a `kind → topology` lookup the Domain cannot own.
    ///
    /// **Intentional:** `kind` and `topology` can be inconsistent — `CanvasShape(kind: "line",
    /// topology: .box)` is constructible. This is allowed on purpose: `topology`, not `kind`,
    /// drives behaviour, and the `ShapeService` clamp tests rely on pairing a `kind` with a
    /// deliberately mismatched `topology` to prove the switch keys off `topology`. Do not "fix"
    /// this by deriving `topology` from `kind`.
    ///
    /// **Registry-vs-persisted invariant:** `ShapeDefinition.topology` is authoritative ONLY at
    /// creation (the registry writes it once into this field via `ShapeService.adding`). Thereafter
    /// the persisted `CanvasShape.topology` wins and the two may legitimately diverge (definition
    /// later changed or removed) — so draw/hit-test/resize must read this persisted field, never
    /// re-derive the topology from the registry.
    var topology: ShapeTopology
    var position: CanvasPosition
    var size: ShapeSize
    var style: CanvasShapeStyle
    /// **Segment only.** Which diagonal of the bounding box the segment runs along, so a line can
    /// be dragged to any angle by its two endpoints. `false` = top-left → bottom-right ("╲", the
    /// original behaviour); `true` = bottom-left → top-right ("╱"). A segment's two endpoints are
    /// the two opposite corners of `size`'s box picked by this flag; horizontal/vertical lines
    /// fall out as a near-zero-height/width box. Ignored for box shapes.
    var lineRising: Bool
    /// Stacking order within a card's canvas — shared with stickies; higher draws in front.
    var sortIndex: Int

    init(
        id: UUID = UUID(),
        cardID: Card.ID,
        kind: String,
        topology: ShapeTopology = .box,
        position: CanvasPosition,
        size: ShapeSize = .default,
        style: CanvasShapeStyle = .default,
        lineRising: Bool = false,
        sortIndex: Int
    ) {
        self.id = id
        self.cardID = cardID
        self.kind = kind
        self.topology = topology
        self.position = position
        self.size = size
        self.style = style
        self.lineRising = lineRising
        self.sortIndex = sortIndex
    }
}
