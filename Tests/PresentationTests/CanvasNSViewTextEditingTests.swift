import AppKit
import XCTest
@testable import KanvasCore

/// Presentation-side coverage for `commitEditing()` on a free-text object (ticket 7C1D6316).
///
/// Review finding r3-1: a palette-dropped text starts empty (`AddTextRequest content: ""`), is
/// persisted, then enters inline editing. The ticket's 決め事 2 requires an empty body to auto-delete
/// on edit-commit — which only happens when `editText` reaches `TextService.editing`. The old
/// unchanged-content guard early-returned when the dropped text's stored content ("") equalled the
/// editor's content (""), so `editText` never fired and an invisible orphan stayed persisted. The
/// fix forces `editText` whenever the trimmed body is empty; these tests pin that contract.
///
/// The view defaults to `scale == 1`, `pan == .zero`, so `viewRect` is non-degenerate for the
/// fixture frame — `beginEditingText` installs the editor and arms `editingID`.
@MainActor
final class CanvasNSViewTextEditingTests: XCTestCase {

    private var view: CanvasNSView!
    private var actions: SpyTextActionHandler!
    private let textID = UUID()

    override func setUp() {
        super.setUp()
        view = CanvasNSView()
        actions = SpyTextActionHandler()
        view.actions = actions
    }

    override func tearDown() {
        view = nil
        actions = nil
        super.tearDown()
    }

    func testCommitEditing_emptyTextDismissedUnchanged_firesEditTextToDelete() {
        pushTextScene(content: "")
        view.beginEditingText(textFixture(content: ""))
        // Editor content unchanged from the stored "" — the old guard would skip editText here.

        view.commitEditing()

        XCTAssertEqual(actions.editTextCalls.count, 1,
                       "An empty dropped text dismissed without typing must route through editText "
                       + "so the domain transform deletes the orphan (決め事 2)")
        XCTAssertEqual(actions.editTextCalls.first?.id, textID)
        XCTAssertEqual(actions.editTextCalls.first?.content, "")
    }

    func testCommitEditing_whitespaceOnlyUnchanged_firesEditTextToDelete() {
        pushTextScene(content: "   ")
        view.beginEditingText(textFixture(content: "   "))

        view.commitEditing()

        XCTAssertEqual(actions.editTextCalls.count, 1,
                       "A whitespace-only body is empty in the domain, so it must still route through "
                       + "editText to delete")
    }

    func testCommitEditing_unchangedNonEmptyText_firesNoEditText() {
        pushTextScene(content: "hello")
        view.beginEditingText(textFixture(content: "hello"))

        view.commitEditing()

        XCTAssertTrue(actions.editTextCalls.isEmpty,
                      "An unchanged non-empty body skips the persist round-trip")
    }

    func testCommitEditing_changedText_firesEditText() {
        pushTextScene(content: "hello")
        view.beginEditingText(textFixture(content: "hello"))
        view.editor.string = "world"

        view.commitEditing()

        XCTAssertEqual(actions.editTextCalls.count, 1)
        XCTAssertEqual(actions.editTextCalls.first?.content, "world")
    }

    // MARK: - Helpers

    private func pushTextScene(content: String) {
        view.update(
            CanvasContent(stickies: [], shapes: [], images: [], texts: [textFixture(content: content)],
                          connectors: []),
            selectedIDs: [], settings: nil, global: nil
        )
    }

    private func textFixture(content: String) -> TextResponse {
        TextResponse(
            id: textID, content: content,
            positionX: 0, positionY: 0, width: 120, height: 40,
            minWidth: 20, minHeight: 20, maxWidth: 600, maxHeight: 600,
            textColorHex: "000000", fontSize: 13, minFontSize: 6, maxFontSize: 96, sortIndex: 0
        )
    }
}

// MARK: - Spy action handler
//
// Captures the editText calls commitEditing emits; every other action is a no-op. The canvas routes
// state changes through CanvasActionHandler, so a spy at that seam is the headless observation point.

@MainActor
private final class SpyTextActionHandler: CanvasActionHandler {

    private(set) var editTextCalls: [(id: UUID, content: String)] = []
    private(set) var copyTextCalls: [UUID] = []
    private(set) var pasteTextCallCount = 0

    func editText(id: UUID, content: String) {
        editTextCalls.append((id: id, content: content))
    }

    func copyText(id: UUID) { copyTextCalls.append(id) }
    func pasteText() { pasteTextCallCount += 1 }

    // Unused by these tests — no-ops to satisfy the protocol.
    func addSticky(worldX: Double, worldY: Double, presetID: UUID) {}
    func moveSticky(id: UUID, worldX: Double, worldY: Double) {}
    func setStickyFrame(id: UUID, worldFrame: CGRect) {}
    func selectSticky(id: UUID?) {}
    func toggleSelection(id: UUID) {}
    func selectRegion(ids: Set<UUID>, additive: Bool) {}
    func moveSelected(_ moves: [CanvasDragMove]) {}
    func deleteSelected(ids: [UUID]) {}
    func editSticky(id: UUID, content: String) {}
    func deleteSticky(id: UUID) {}
    func copySticky(id: UUID) {}
    func pasteSticky() {}
    func bringStickyToFront(id: UUID) {}
    func sendStickyToBack(id: UUID) {}
    func openLabelManager(stickyID: UUID) {}
    func undo() {}
    func imageData(assetID: UUID) async -> CanvasImageLoad { .transientFailure }
    func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason) {}
    func addShape(_ draft: ShapeDraft) {}
    func moveShape(id: UUID, worldX: Double, worldY: Double) {}
    func resizeShape(id: UUID, worldFrame: CGRect, lineRising: Bool?) {}
    func selectShape(id: UUID?) {}
    func deleteShape(id: UUID) {}
    func bringShapeToFront(id: UUID) {}
    func sendShapeToBack(id: UUID) {}
    func addImage(worldX: Double, worldY: Double, payload: CanvasImagePayload) {}
    func moveImage(id: UUID, worldX: Double, worldY: Double) {}
    func resizeImage(id: UUID, worldFrame: CGRect) {}
    func selectImage(id: UUID?) {}
    func deleteImage(id: UUID) {}
    func bringImageToFront(id: UUID) {}
    func sendImageToBack(id: UUID) {}
    func addText(worldX: Double, worldY: Double) {}
    func moveText(id: UUID, worldX: Double, worldY: Double) {}
    func setTextFrame(id: UUID, worldFrame: CGRect) {}
    func selectText(id: UUID?) {}
    func deleteText(id: UUID) {}
    func bringTextToFront(id: UUID) {}
    func sendTextToBack(id: UUID) {}
    func reconnectConnector(_ gesture: ConnectorReconnectGesture) {}
    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) {}
    func growConnector(_ gesture: ConnectorGrowGesture) {}
    func selectConnector(id: UUID?) {}
    func deleteConnector(id: UUID) {}
}
