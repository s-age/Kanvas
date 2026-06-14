/// A 2-D displacement in world units — the generic delta sibling of `CanvasPosition` (an absolute
/// world point). A value-object relative shift `(dx, dy)`; the receiver decides what it is measured
/// from. (Current sole use: a connector's waypoint offset, stored relative to the midpoint of its two
/// endpoint edge midpoints so the deformed route follows its stickies — see `Connector`.)
struct CanvasOffset: Sendable, Equatable {
    var dx: Double
    var dy: Double

    static let zero = CanvasOffset(dx: 0, dy: 0)
}
