import Foundation

/// Deletes a multi-selection of canvas items in one batch (one undo entry — ticket 4FF14DCF). Ids
/// may name stickies, shapes, images, or connectors; the kind is resolved in the Domain layer.
struct DeleteCanvasGroupRequest: UseCaseRequest {
    let ids: [UUID]
    /// The card whose canvas owns the elements. Supplied so the mutation can return that card's
    /// refreshed detail — the elements are gone post-delete, so their owner can't be resolved from
    /// the result. `nil` (the default) when the caller has no open card: the response then carries
    /// no detail and the caller falls back to a fresh load (ticket 1DCBF9C9).
    let cardID: UUID?

    init(ids: [UUID], cardID: UUID? = nil) {
        self.ids = ids
        self.cardID = cardID
    }
}
