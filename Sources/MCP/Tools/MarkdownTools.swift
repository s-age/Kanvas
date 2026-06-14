import KanvasCore
import MCP

/// `markdown_*` tools — a card's Markdown detail (the right-pane editor content). Read and write the
/// `markdownContent` of a card; both return {cardID, title, markdownContent}.
func markdownTools(_ gateway: KanvasMCPGateway) -> [any MCPTool] {
    [
        ClosureTool(
            name: "markdown_get",
            description: "Get a card's Markdown detail. Returns {cardID, title, markdownContent}.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
            ])
        ) { args in try await gateway.getMarkdown(cardID: args.string("cardID")) },

        ClosureTool(
            name: "markdown_set",
            description: "Replace a card's Markdown detail with 'content'. Returns the refreshed {cardID, title, markdownContent}.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("content", "string", "The full Markdown content to set.", true),
            ])
        ) { args in
            try await gateway.setMarkdown(cardID: args.string("cardID"), content: args.string("content"))
        },

        ClosureTool(
            name: "markdown_add_image",
            description: "Create a new image asset from base64-encoded PNG bytes and append its "
                + "reference to the card's Markdown body (the drag-drop / paste equivalent for MCP). "
                + "Returns the refreshed {cardID, title, markdownContent}.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("imageBase64", "string", "Base64-encoded PNG image bytes for the new asset.", true),
            ])
        ) { args in
            try await gateway.addMarkdownImage(
                cardID: args.string("cardID"), imageBase64: args.string("imageBase64")
            )
        },

        ClosureTool(
            name: "markdown_delete_image",
            description: "Remove the first kanvas-asset reference to 'assetID' from the card's "
                + "Markdown body (the gallery delete-button equivalent for MCP). The asset's bytes "
                + "are deleted only when no card references it any more; a still-referenced asset "
                + "keeps its bytes. Returns the refreshed {cardID, title, markdownContent}.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("assetID", "string", "UUID of the image asset to remove a reference to.", true),
            ])
        ) { args in
            try await gateway.deleteMarkdownImage(
                cardID: args.string("cardID"), assetID: args.string("assetID")
            )
        },
    ]
}
