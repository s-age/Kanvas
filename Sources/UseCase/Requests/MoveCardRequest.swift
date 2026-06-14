import Foundation

struct MoveCardRequest: UseCaseRequest {
    let cardID: UUID
    let toColumnID: UUID
    /// The card the moved card should land immediately before, or `nil` to append to the end
    /// of the target column. Resolving this anchor into a concrete insertion index is the
    /// Domain's job (`CardService.moving`) — Presentation only reports where the drop landed.
    let beforeCardID: UUID?
}
