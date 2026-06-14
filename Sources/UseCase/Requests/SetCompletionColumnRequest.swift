import Foundation

struct SetCompletionColumnRequest: UseCaseRequest {
    let columnID: UUID
    let isCompletion: Bool
}
