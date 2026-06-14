import Foundation

/// Creation input for a new connector, bundled so `ConnectorService.add` stays within the
/// parameter-count budget (the `*Seed` / `*Placement` pattern). It carries the source endpoint, the
/// target's two possible shapes (an existing sticky **or** a placement for a brand-new one), and the
/// explicit stroke colour.
///
/// `existingTargetStickyID` and `newStickyPlacement` are the two target paths the service chooses
/// between: a non-nil `existingTargetStickyID` links that sticky; otherwise a new free sticky is
/// created at `newStickyPlacement` and used as the target — both the sticky and the connector commit
/// in one mutation (one undo).
struct ConnectorSeed: Sendable, Equatable {
    var sourceStickyID: Sticky.ID
    var sourceEdge: CanvasEdge
    var targetEdge: CanvasEdge
    /// The target sticky to link, or `nil` to grow a new one at `newStickyPlacement`.
    var existingTargetStickyID: Sticky.ID?
    /// Where the new target sticky lands when `existingTargetStickyID` is `nil`; ignored otherwise.
    var newStickyPlacement: StickyPlacement
    /// The explicit stroke colour the caller chose, or `nil` to inherit the canvas-contrasting
    /// default (see `ConnectorService.adding`).
    var strokeColorHex: String?

    init(
        sourceStickyID: Sticky.ID,
        sourceEdge: CanvasEdge,
        targetEdge: CanvasEdge,
        existingTargetStickyID: Sticky.ID? = nil,
        newStickyPlacement: StickyPlacement,
        strokeColorHex: String? = nil
    ) {
        self.sourceStickyID = sourceStickyID
        self.sourceEdge = sourceEdge
        self.targetEdge = targetEdge
        self.existingTargetStickyID = existingTargetStickyID
        self.newStickyPlacement = newStickyPlacement
        self.strokeColorHex = strokeColorHex
    }
}
