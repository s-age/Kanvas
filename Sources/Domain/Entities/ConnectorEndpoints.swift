/// The two ends of a connector — each a sticky plus the edge it attaches to. Bundling them keeps
/// `ConnectorService.adding` to a single endpoint argument (mirrors how `StickyPlacement` bundles
/// position + size).
struct ConnectorEndpoints: Sendable, Equatable {
    var sourceStickyID: Sticky.ID
    var sourceEdge: CanvasEdge
    var targetStickyID: Sticky.ID
    var targetEdge: CanvasEdge
}
