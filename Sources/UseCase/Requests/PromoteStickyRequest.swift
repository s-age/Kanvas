import Foundation

struct PromoteStickyRequest: UseCaseRequest {
    let stickyID: UUID
    let toColumnID: UUID
}
