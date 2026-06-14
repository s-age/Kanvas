/// One end of a connector — a sticky plus the edge it attaches to. The single-side counterpart of
/// `ConnectorEndpoints` (which bundles both ends for `adding`): a reconnect names only the side(s)
/// being moved, so `ConnectorService.reconnect` takes an optional `ConnectorEndpoint` per side and
/// leaves a `nil` side untouched.
struct ConnectorEndpoint: Sendable, Equatable {
    let stickyID: Sticky.ID
    let edge: CanvasEdge
}
