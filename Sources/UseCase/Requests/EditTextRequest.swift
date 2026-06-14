import Foundation

/// Changes a free-text object's body. An empty body (after trimming) auto-deletes the text object
/// in the Domain transform (`TextService.editing`) — the canvas never keeps a blank text object.
/// The *upper* bound still applies (the MCP `canvas_text_edit` tool can hand an unbounded string),
/// using the same `stickyContent` cap as the sibling sticky requests. (ticket C5994D2A)
struct EditTextRequest: ValidatableRequest {
    let textID: UUID
    let content: String

    func validate() throws {
        try ContentSizeValidation.validate(stickyContent: content)
    }
}
