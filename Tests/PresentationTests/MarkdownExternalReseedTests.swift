import XCTest
@testable import KanvasCore

/// Tests for `MarkdownEditorView.ExternalNotesRewrite` — the pure gate deciding whether
/// an externally rewritten `markdownContent` (e.g. `markdown_set` via MCP, surfaced through
/// `BoardStoreWatcher` → `selectedCardDetail`) is adopted into the editor's local draft.
///
/// The contract (PR #38, extended in ticket B817F0D2):
/// - Adopt only for the card currently being edited (id match, non-nil).
/// - Self-echo of our own save (`newContent == loadedContent`) is a no-op.
/// - An unsaved local edit (`draft != loadedContent`) keeps local — last-writer-wins
///   via its autosave; the external content is NOT adopted over a dirty draft.
/// - An edit still owed to the disk by the autosave channel (`hasPendingSave`) keeps local
///   even when the de-dup baseline already advanced past it (`draft == loadedContent`).
final class MarkdownExternalReseedTests: XCTestCase {

    private let cardID = UUID()
    private let otherCardID = UUID()

    func testAdoptsExternalContentForCleanDraftOnEditedCard() {
        XCTAssertTrue(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "rewritten by MCP",
                detailCardID: cardID,
                editingCardID: cardID,
                draft: "saved",
                loadedContent: "saved",
                hasPendingSave: false
            ).shouldAdopt
        )
    }

    func testIgnoresSelfEchoOfOwnSave() {
        // save() advances loadedContent when it enqueues; the watcher then reloads the detail
        // with identical content — adopting it would be pointless churn.
        XCTAssertFalse(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "just saved locally",
                detailCardID: cardID,
                editingCardID: cardID,
                draft: "just saved locally",
                loadedContent: "just saved locally",
                hasPendingSave: false
            ).shouldAdopt
        )
    }

    func testKeepsDirtyLocalDraftOverExternalContent() {
        // Unsaved local typing wins (last-writer-wins via its pending autosave).
        XCTAssertFalse(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "rewritten by MCP",
                detailCardID: cardID,
                editingCardID: cardID,
                draft: "saved plus unsaved typing",
                loadedContent: "saved",
                hasPendingSave: false
            ).shouldAdopt
        )
    }

    func testKeepsLocalWhileAutosaveChannelStillOwesTheDisk() {
        // The de-dup baseline advances the instant text is enqueued (draft == loadedContent),
        // but the channel has not yet persisted it. Adopting the external content here would
        // clobber a local edit that is about to land — the pending flag keeps local.
        XCTAssertFalse(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "rewritten by MCP",
                detailCardID: cardID,
                editingCardID: cardID,
                draft: "enqueued not yet written",
                loadedContent: "enqueued not yet written",
                hasPendingSave: true
            ).shouldAdopt
        )
    }

    func testIgnoresContentForAForeignCard() {
        // Card-switch ordering: the content onChange can fire while the detail already points
        // at the next card but `editingCardID` still names the previous one (or vice versa).
        XCTAssertFalse(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "other card's notes",
                detailCardID: otherCardID,
                editingCardID: cardID,
                draft: "saved",
                loadedContent: "saved",
                hasPendingSave: false
            ).shouldAdopt
        )
    }

    func testIgnoresWhenNoCardIsBeingEditedYet() {
        // Before the first load() both ids can be nil; nil == nil must not count as a match.
        XCTAssertFalse(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "content",
                detailCardID: nil,
                editingCardID: nil,
                draft: "",
                loadedContent: "",
                hasPendingSave: false
            ).shouldAdopt
        )
    }

    func testAdoptsExternalClearWhenDraftIsClean() {
        // An external rewrite to empty is still a legitimate new state for a clean buffer.
        XCTAssertTrue(
            MarkdownEditorView.ExternalNotesRewrite(
                newContent: "",
                detailCardID: cardID,
                editingCardID: cardID,
                draft: "saved",
                loadedContent: "saved",
                hasPendingSave: false
            ).shouldAdopt
        )
    }
}
