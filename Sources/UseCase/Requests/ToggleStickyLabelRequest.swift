import Foundation

struct ToggleStickyLabelRequest: UseCaseRequest {
    let stickyID: UUID
    let labelID: UUID
}
