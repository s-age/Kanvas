import Foundation

struct DeleteConnectorRequest: UseCaseRequest {
    let connectorID: UUID
    /// The card whose canvas owns the element. Supplied so the mutation can return that card's
    /// refreshed detail — the element is gone post-delete, so its owner can't be resolved from the
    /// result. `nil` (the default) when the caller has no open card: the response then carries no
    /// detail and the caller falls back to a fresh load (ticket 1DCBF9C9).
    let cardID: UUID?

    init(connectorID: UUID, cardID: UUID? = nil) {
        self.connectorID = connectorID
        self.cardID = cardID
    }
}
