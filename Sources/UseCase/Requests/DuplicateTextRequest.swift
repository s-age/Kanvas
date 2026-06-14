import Foundation

/// Copies an existing free-text object to a new position on the same card's canvas. Mirrors
/// `DuplicateStickyRequest` — backs ⌘C/⌘V paste of a selected text.
struct DuplicateTextRequest: UseCaseRequest {
    let textID: UUID
    let positionX: Double
    let positionY: Double
}
