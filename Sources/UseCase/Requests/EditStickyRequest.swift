import Foundation

struct EditStickyRequest: ValidatableRequest {
    let stickyID: UUID
    let content: String

    // A blank sticky is valid (an empty note on the canvas), so only the upper bound is checked.
    func validate() throws {
        try ContentSizeValidation.validate(stickyContent: content)
    }
}
