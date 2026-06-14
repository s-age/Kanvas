import Foundation

/// A directed link between two stickies on a card's canvas. Each end attaches to a specific
/// `CanvasEdge` of its sticky; the drawn endpoint is that edge's midpoint, recomputed from the
/// sticky's live rect — so the connector follows its stickies as they move or resize. Unlike
/// `CanvasShape`, a connector carries no geometry of its own and does **not** join the canvas
/// `sortIndex` z-order: connectors render in a dedicated pass behind all stickies/shapes.
///
/// Both ends are stickies; a connector is removed when either endpoint sticky is deleted
/// (cascade in `StickyService.deleting`).
struct Connector: Sendable, Identifiable, Equatable {
    let id: UUID
    var cardID: Card.ID
    var sourceStickyID: Sticky.ID
    var sourceEdge: CanvasEdge
    var targetStickyID: Sticky.ID
    var targetEdge: CanvasEdge
    var style: ConnectorStyle
    /// Optional waypoint (midpoint deformation) for an `elbow`/`curve` route: the offset of the
    /// central drag handle from the midpoint of the two endpoint edge midpoints. `nil` = no waypoint
    /// (the automatic route — the current elbow/curve shape). Non-`nil` bends the route through
    /// `midpoint(sourceMid, targetMid) + waypointOffset`. Stored relative to that midpoint so the
    /// deformed connector translates with its stickies as they move. Ignored for `straight` routing.
    var waypointOffset: CanvasOffset?

    init(
        id: UUID = UUID(),
        cardID: Card.ID,
        sourceStickyID: Sticky.ID,
        sourceEdge: CanvasEdge,
        targetStickyID: Sticky.ID,
        targetEdge: CanvasEdge,
        style: ConnectorStyle = .default,
        waypointOffset: CanvasOffset? = nil
    ) {
        self.id = id
        self.cardID = cardID
        self.sourceStickyID = sourceStickyID
        self.sourceEdge = sourceEdge
        self.targetStickyID = targetStickyID
        self.targetEdge = targetEdge
        self.style = style
        self.waypointOffset = waypointOffset
    }
}
