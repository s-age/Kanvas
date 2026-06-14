import Foundation

// Canvas-element → owning-card lookups. A canvas-mutation use case uses these to resolve the card
// whose canvas it just changed (from the post-mutation state) so it can attach that card's refreshed
// detail to its `BoardMutationResponse` — eliminating the redundant card-detail reload (ticket
// 1DCBF9C9). Each returns `nil` when no element matches (e.g. it was just deleted); the caller then
// supplies the owning card id another way (a `delete` request carries it) or leaves the detail unset.
extension BoardState {
    func ownerCardID(ofSticky id: Sticky.ID) -> Card.ID? {
        stickies.first { $0.id == id }?.cardID
    }

    func ownerCardID(ofShape id: CanvasShape.ID) -> Card.ID? {
        shapes.first { $0.id == id }?.cardID
    }

    func ownerCardID(ofImage id: CanvasImage.ID) -> Card.ID? {
        images.first { $0.id == id }?.cardID
    }

    func ownerCardID(ofText id: CanvasText.ID) -> Card.ID? {
        texts.first { $0.id == id }?.cardID
    }

    func ownerCardID(ofConnector id: Connector.ID) -> Card.ID? {
        connectors.first { $0.id == id }?.cardID
    }
}
