import Foundation

/// `canvas_*` (a card's stickies) and `markdown_*` (a card's Markdown detail) operations.
///
/// The sticky write ops take the owning `cardID` so they can echo that card's refreshed canvas.
/// Each underlying use case returns a `BoardMutationResponse` that already carries the affected
/// card's detail, so the gateway echoes that directly instead of re-reading it from disk — only
/// falling back to a load when the mutation supplied no detail for this card (ticket 1DCBF9C9).
extension KanvasMCPGateway {

    // MARK: - Canvas (stickies)

    public func getCanvas(cardID: String) async throws -> String {
        try await MCPJSON.encode(CardDetailOut(cardDetail(cardID: uuid(cardID, "cardID"))))
    }

    public func addSticky(
        cardID: String, content: String, frame: StickyFrame, fillColorHex: String?
    ) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await addStickyUseCase.execute(AddStickyRequest(
            cardID: id, content: content,
            positionX: frame.x, positionY: frame.y, width: frame.width, height: frame.height,
            fillColorHex: fillColorHex
        ))
        return try await canvasJSON(result, cardID: id)
    }

    public func editSticky(cardID: String, stickyID: String, content: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await editStickyUseCase.execute(
            EditStickyRequest(stickyID: uuid(stickyID, "stickyID"), content: content)
        )
        return try await canvasJSON(result, cardID: id)
    }

    public func moveSticky(cardID: String, stickyID: String, x: Double, y: Double) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await moveStickyUseCase.execute(
            MoveStickyRequest(stickyID: uuid(stickyID, "stickyID"), positionX: x, positionY: y)
        )
        return try await canvasJSON(result, cardID: id)
    }

    public func setStickyFrame(cardID: String, stickyID: String, frame: StickyFrame) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await setStickyFrameUseCase.execute(SetStickyFrameRequest(
            stickyID: uuid(stickyID, "stickyID"),
            width: frame.width, height: frame.height, positionX: frame.x, positionY: frame.y
        ))
        return try await canvasJSON(result, cardID: id)
    }

    public func deleteSticky(cardID: String, stickyID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await deleteStickyUseCase.execute(
            DeleteStickyRequest(stickyID: uuid(stickyID, "stickyID"), cardID: id)
        )
        return try await canvasJSON(result, cardID: id)
    }

    /// Promotes a free sticky to a task sticky — creates a card in `toColumnID` and links it.
    public func promoteSticky(cardID: String, stickyID: String, toColumnID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await promoteStickyUseCase.execute(PromoteStickyRequest(
            stickyID: uuid(stickyID, "stickyID"), toColumnID: uuid(toColumnID, "toColumnID")
        ))
        return try await canvasJSON(result, cardID: id)
    }

    /// Demotes a task sticky back to a free sticky — clears its Kanban link.
    public func demoteSticky(cardID: String, stickyID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await demoteStickyUseCase.execute(DemoteStickyRequest(stickyID: uuid(stickyID, "stickyID")))
        return try await canvasJSON(result, cardID: id)
    }

    // MARK: - Canvas (free-text objects)

    public func addText(cardID: String, content: String, frame: StickyFrame) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await addTextUseCase.execute(AddTextRequest(
            cardID: id, content: content,
            positionX: frame.x, positionY: frame.y, width: frame.width, height: frame.height
        ))
        return try await canvasJSON(result, cardID: id)
    }

    /// Edits a text object's content and, optionally, its style (colour / font size) — each provided
    /// field is a separate mutation applied in sequence (content, then colour, then font size). A
    /// blank content auto-deletes the text object (`TextService.editing`); when that happens the
    /// style setters are skipped — restyling a just-deleted text is nonsensical and would otherwise
    /// throw `notFound` on the now-missing id, so the delete wins and is reported as a clean success.
    public func editText(cardID: String, textID: String, content: String,
                         style: TextStyleEdit) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let tid = try uuid(textID, "textID")
        _ = try await editTextUseCase.execute(EditTextRequest(textID: tid, content: content))
        // A blank body auto-deletes the text, so the id no longer resolves — skip the style setters
        // (they would throw `notFound` on the deleted text). The delete is the intended outcome.
        let isDeleted = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !isDeleted, let colorHex = style.colorHex {
            _ = try await setTextColorUseCase.execute(SetTextColorRequest(textID: tid, colorHex: colorHex))
        }
        if !isDeleted, let fontSize = style.fontSize {
            _ = try await setTextFontSizeUseCase.execute(SetTextFontSizeRequest(textID: tid, fontSize: fontSize))
        }
        return try await canvasJSON(cardID: id)
    }

    public func moveText(cardID: String, textID: String, x: Double, y: Double) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await moveTextUseCase.execute(
            MoveTextRequest(textID: uuid(textID, "textID"), positionX: x, positionY: y)
        )
        return try await canvasJSON(result, cardID: id)
    }

    public func setTextFrame(cardID: String, textID: String, frame: StickyFrame) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await resizeTextUseCase.execute(ResizeTextRequest(
            textID: uuid(textID, "textID"),
            width: frame.width, height: frame.height, positionX: frame.x, positionY: frame.y
        ))
        return try await canvasJSON(result, cardID: id)
    }

    public func deleteText(cardID: String, textID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await deleteTextUseCase.execute(
            DeleteTextRequest(textID: uuid(textID, "textID"), cardID: id)
        )
        return try await canvasJSON(result, cardID: id)
    }

    // MARK: - Markdown

    public func getMarkdown(cardID: String) async throws -> String {
        let detail = try await cardDetail(cardID: uuid(cardID, "cardID"))
        return try MCPJSON.encode(
            MarkdownOut(cardID: detail.id, title: detail.title, markdownContent: detail.markdownContent)
        )
    }

    public func setMarkdown(cardID: String, content: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await editCardUseCase.execute(EditCardRequest(
            cardID: id, title: nil, markdownContent: content,
            schedule: nil, labels: nil, assignee: nil
        ))
        let detail = try await echoDetail(result, cardID: id)
        return try MCPJSON.encode(
            MarkdownOut(cardID: detail.id, title: detail.title, markdownContent: detail.markdownContent)
        )
    }

    /// Mints a new image asset from base64-encoded PNG bytes and embeds a `kanvas-asset://<id>`
    /// reference at the end of the card's Markdown body — the MCP equivalent of the editor's
    /// drag-drop / ⌘V import (drop was previously the only asset-creation path). Reuses the same
    /// `SaveImageAssetUseCase` / `CanvasImageService.saveAsset` plumbing as the editor (same
    /// validation, same store), then appends the reference via `editCardUseCase` so the inline
    /// renderer and the orphan-GC Markdown scan both see it exactly as a dropped image. Returns the
    /// refreshed {cardID, title, markdownContent}.
    public func addMarkdownImage(cardID: String, imageBase64: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        // Reject an over-cap payload on its base64 string length alone, before `Data(base64Encoded:)`
        // allocates the decoded blob — the UseCase's 32MB cap (`SaveImageAssetRequest`) would reject
        // it anyway, so this only avoids the wasted decode of a giant input (ticket F20D872C). The
        // threshold derives from the same `ContentSizeValidation.maxImageByteCount` source and fires
        // only when the length's *minimum* possible decode exceeds the cap, so it never rejects
        // something the UseCase would accept (see `MCPImageValidation.exceedsImageByteCap`).
        guard !MCPImageValidation.exceedsImageByteCap(base64Length: imageBase64.count) else {
            throw KanvasMCPError.imageTooLarge(field: "imageBase64", maxBytes: ContentSizeValidation.maxImageByteCount)
        }
        guard let imageData = Data(base64Encoded: imageBase64) else {
            throw KanvasMCPError.badBase64(field: "imageBase64")
        }
        // The asset is stored verbatim as assets/<id>.png and decoded only later at render time, so
        // validate the PNG signature up front — a non-PNG payload (or a JPEG/GIF the caller named PNG)
        // fails loudly here at the source instead of surfacing as an undecodable image when rendered.
        guard MCPImageValidation.isPNG(imageData) else {
            throw KanvasMCPError.notPNG(field: "imageBase64")
        }
        // Save the asset first; the use case validates non-empty + size bounds (same as drop).
        let saved = try await saveImageAssetUseCase.execute(SaveImageAssetRequest(imageData: imageData))
        // Append the reference on its own line (trailing newline too), mirroring the editor drop
        // path's "\n<reference>\n" own-line insertion; skip the leading newline when the body is empty.
        let existing = try await cardDetail(cardID: id).markdownContent
        let reference = MarkdownImageReference.markdown(for: saved.assetID)
        let leading = existing.isEmpty ? "" : "\n"
        let result = try await editCardUseCase.execute(EditCardRequest(
            cardID: id, title: nil, markdownContent: existing + leading + reference + "\n",
            schedule: nil, labels: nil, assignee: nil
        ))
        let detail = try await echoDetail(result, cardID: id)
        return try MCPJSON.encode(
            MarkdownOut(cardID: detail.id, title: detail.title, markdownContent: detail.markdownContent)
        )
    }

    /// Removes the **first** `kanvas-asset://<assetID>` reference from the card's Markdown body — the
    /// MCP counterpart of the gallery's delete button, symmetric with `addMarkdownImage`. When no
    /// card / board / Canvas placement still references the asset after the removal, its on-disk bytes
    /// are reclaimed immediately (refcount); a still-referenced asset keeps its bytes so no other
    /// reference breaks. Throws `notFound` when the card or the reference is absent (no phantom
    /// success). Returns the refreshed {cardID, title, markdownContent}.
    public func deleteMarkdownImage(cardID: String, assetID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await deleteMarkdownImageUseCase.execute(DeleteMarkdownImageRequest(
            cardID: id, assetID: uuid(assetID, "assetID")
        ))
        let detail = try await echoDetail(result, cardID: id)
        return try MCPJSON.encode(
            MarkdownOut(cardID: detail.id, title: detail.title, markdownContent: detail.markdownContent)
        )
    }

    // MARK: - Helpers

    /// Loads a card's detail, throwing `notFound` when the id matches no card. Shared with the
    /// `board_*` gateway (e.g. `setCardPRURL`), so it is `internal`, not file-private. Echoes the
    /// **parsed** id (`cardID.uuidString`, uppercase-normalized) — matching the domain backstop's
    /// `UUID.uuidString` — so a stale card id renders identically whichever guard fires (ticket
    /// 0D2DE256); the caller's parsed `cardID` is the single source, so no raw string is threaded.
    func cardDetail(cardID: UUID) async throws -> CardDetailResponse {
        guard let detail = try await loadCardDetailUseCase.execute(cardID: cardID) else {
            throw KanvasMCPError.notFound(kind: "Card", id: cardID.uuidString)
        }
        return detail
    }

    /// The card detail to echo after a write — the detail the mutation already returned (no extra
    /// disk read), or a fresh load only when the mutation supplied none for this card (ticket
    /// 1DCBF9C9). The `id == cardID` guard keeps the echo card-scoped: a write whose returned detail
    /// is for a different card (an inconsistent `cardID` argument) still reloads the requested card.
    func echoDetail(_ mutation: BoardMutationResponse, cardID: UUID) async throws -> CardDetailResponse {
        if let detail = mutation.cardDetail, detail.id == cardID { return detail }
        return try await cardDetail(cardID: cardID)
    }

    /// Encodes a card's refreshed canvas from a write's result — the uniform echo of every canvas
    /// write, preferring the detail the mutation carried. Shared with the connector gateway.
    func canvasJSON(_ mutation: BoardMutationResponse, cardID: UUID) async throws -> String {
        try await MCPJSON.encode(CardDetailOut(echoDetail(mutation, cardID: cardID)))
    }

    /// Encodes a card's refreshed canvas by loading it fresh — used by read paths and pre-checks
    /// that have no mutation result in hand. Shared with the connector gateway (`+Connector`).
    func canvasJSON(cardID: UUID) async throws -> String {
        try await MCPJSON.encode(CardDetailOut(cardDetail(cardID: cardID)))
    }
}
