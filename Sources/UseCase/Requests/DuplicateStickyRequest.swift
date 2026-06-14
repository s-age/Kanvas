import Foundation

struct DuplicateStickyRequest: UseCaseRequest {
    let stickyID: UUID
    let positionX: Double
    let positionY: Double
}
