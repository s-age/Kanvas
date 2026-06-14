import Foundation

struct ReorderColumnRequest: UseCaseRequest {
    let columnID: UUID
    let beforeColumnID: UUID?
}
