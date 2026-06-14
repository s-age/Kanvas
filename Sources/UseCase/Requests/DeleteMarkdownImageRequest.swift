import Foundation

/// Deletes a Markdown inline image from a card: removes the first `kanvas-asset://<assetID>` reference
/// from the card's body and reclaims the asset bytes when no card/Canvas placement on any board still
/// references that id (a refcount). The MCP `markdown_delete_image` tool and the gallery's per-image
/// delete button both route here. No invariant to validate — both ids are plain UUIDs the domain
/// resolves, throwing `notFound` for a missing card or reference — so it is a bare `UseCaseRequest`.
struct DeleteMarkdownImageRequest: UseCaseRequest {
    let cardID: UUID
    let assetID: UUID
}
