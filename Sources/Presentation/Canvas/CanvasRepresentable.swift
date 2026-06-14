import SwiftUI

/// The outcome of a draw-time image-asset fetch, returned to the canvas so it can tell a **terminal**
/// failure (negative-cache it — never re-fetch) from a **transient** one (retry on the next redraw).
/// Collapsing both to `Data?` (the old shape) made a brief read failure or a vanished handler look
/// identical to a permanently missing asset, pinning the placeholder for the whole session (ticket
/// 37B774CD).
enum CanvasImageLoad: Sendable {
    /// Bytes are available; the canvas decodes them (a decode failure is itself terminal).
    case loaded(Data)
    /// The sidecar asset is genuinely absent — terminal, negative-cache it.
    case unavailable
    /// A fetch error or cancellation (e.g. a transient read during an external atomic replace) — not
    /// terminal; leave it out of the negative cache so the next redraw retries.
    case transientFailure
}

/// Actions the AppKit canvas sends back to the SwiftUI/ViewModel side. The canvas owns
/// display + interaction; all state mutation flows through here so the layer boundary holds.
@MainActor
protocol CanvasActionHandler: AnyObject {
    func addSticky(worldX: Double, worldY: Double, presetID: UUID)
    func moveSticky(id: UUID, worldX: Double, worldY: Double)
    func setStickyFrame(id: UUID, worldFrame: CGRect)
    func selectSticky(id: UUID?)
    /// Multi-select: ⌘-click toggles one item; marquee selects a region (additive when ⌘ held);
    /// group move/delete act on the whole selection. Colour/size stay single-selection only.
    func toggleSelection(id: UUID)
    func selectRegion(ids: Set<UUID>, additive: Bool)
    func moveSelected(_ moves: [CanvasDragMove])
    func deleteSelected(ids: [UUID])
    func editSticky(id: UUID, content: String)
    func deleteSticky(id: UUID)
    func copySticky(id: UUID)
    func pasteSticky()
    func bringStickyToFront(id: UUID)
    func sendStickyToBack(id: UUID)
    func openLabelManager(stickyID: UUID)
    func undo()
    // Shapes — mirror the sticky create/move/resize/delete/z-order/select actions.
    func addShape(_ draft: ShapeDraft)
    func moveShape(id: UUID, worldX: Double, worldY: Double)
    func resizeShape(id: UUID, worldFrame: CGRect, lineRising: Bool?)
    func selectShape(id: UUID?)
    func deleteShape(id: UUID)
    func bringShapeToFront(id: UUID)
    func sendShapeToBack(id: UUID)
    // Images — mirror the create/move/resize/delete/z-order/select actions. `addImage` carries the
    // PNG bytes + source pixel size; `imageData` fetches a placed image's bytes for the canvas to
    // decode + draw (the only action that returns a value, hence `async`).
    func addImage(worldX: Double, worldY: Double, payload: CanvasImagePayload)
    func moveImage(id: UUID, worldX: Double, worldY: Double)
    func resizeImage(id: UUID, worldFrame: CGRect)
    func selectImage(id: UUID?)
    func deleteImage(id: UUID)
    func bringImageToFront(id: UUID)
    func sendImageToBack(id: UUID)
    // Free-text objects — mirror the create/edit/move/resize/delete/z-order/select actions. `addText`
    // creates an empty text at the drop point and the canvas enters inline editing on it once it
    // appears (so a dropped text is immediately typeable).
    func addText(worldX: Double, worldY: Double)
    func copyText(id: UUID)
    func pasteText()
    func editText(id: UUID, content: String)
    func moveText(id: UUID, worldX: Double, worldY: Double)
    func setTextFrame(id: UUID, worldFrame: CGRect)
    func selectText(id: UUID?)
    func deleteText(id: UUID)
    func bringTextToFront(id: UUID)
    func sendTextToBack(id: UUID)
    func imageData(assetID: UUID) async -> CanvasImageLoad
    /// Diagnostics only: the canvas has permanently negative-cached a placed image (missing or
    /// undecodable sidecar) and is showing the placeholder; record why so it is not silent.
    func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason)
    // Connectors — grow from a sticky edge (linking an existing sticky or creating a new one),
    // plus select / delete. Style edits flow from the toolbar straight to the ViewModel.
    func growConnector(_ gesture: ConnectorGrowGesture)
    func selectConnector(id: UUID?)
    /// Re-attaches the dragged end of a selected connector to a different sticky / edge.
    func reconnectConnector(_ gesture: ConnectorReconnectGesture)
    /// Sets a selected elbow/curve connector's waypoint (central deformation) offset, in world units
    /// relative to the midpoint of its two endpoint edge midpoints.
    func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double)
    func deleteConnector(id: UUID)
}

/// Bridges the pure-AppKit `CanvasNSView` into the SwiftUI hierarchy. The bridge is the
/// canvas subsystem's own responsibility (mirrors the Markdown editor's AppKit carve-out).
struct CanvasRepresentable: NSViewRepresentable {
    let viewModel: BoardViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    func makeNSView(context: Context) -> CanvasNSView {
        let view = CanvasNSView()
        view.actions = context.coordinator
        return view
    }

    func updateNSView(_ nsView: CanvasNSView, context: Context) {
        // Read the observable properties here so Observation re-invokes updateNSView when the
        // selected card's stickies change (add / move / reorder) or the selection changes.
        // One selection (sticky or shape); the canvas highlights it by id regardless of kind.
        nsView.update(
            CanvasContent(
                stickies: viewModel.selectedCardDetail?.stickies ?? [],
                shapes: viewModel.selectedCardDetail?.shapes ?? [],
                images: viewModel.selectedCardDetail?.images ?? [],
                texts: viewModel.selectedCardDetail?.texts ?? [],
                connectors: viewModel.selectedCardDetail?.connectors ?? []
            ),
            selectedIDs: viewModel.selectedIDs,
            settings: viewModel.board?.settings.canvas,
            global: viewModel.board?.settings.global
        )
        // A just-dropped (empty) text wants immediate inline editing; the canvas begins editing once
        // the text appears in `texts`, then the VM clears the request so it fires once.
        if let pending = viewModel.textAwaitingEdit, nsView.beginEditingTextIfPresent(id: pending) {
            viewModel.clearTextAwaitingEdit()
        }
    }

    @MainActor
    final class Coordinator: CanvasActionHandler {
        private let viewModel: BoardViewModel

        init(viewModel: BoardViewModel) {
            self.viewModel = viewModel
        }

        func addSticky(worldX: Double, worldY: Double, presetID: UUID) {
            guard let cardID = viewModel.selectedCardID else { return }
            Task { await viewModel.addSticky(cardID: cardID, x: worldX, y: worldY, presetID: presetID) }
        }

        func moveSticky(id: UUID, worldX: Double, worldY: Double) {
            Task { await viewModel.moveSticky(id: id, x: worldX, y: worldY) }
        }

        func setStickyFrame(id: UUID, worldFrame: CGRect) {
            Task { await viewModel.setStickyFrame(id: id, frame: worldFrame) }
        }

        func selectSticky(id: UUID?) {
            viewModel.select(stickyID: id)
        }

        func toggleSelection(id: UUID) {
            viewModel.toggleSelected(id: id)
        }

        func selectRegion(ids: Set<UUID>, additive: Bool) {
            viewModel.selectRegion(ids: ids, additive: additive)
        }

        func moveSelected(_ moves: [CanvasDragMove]) {
            Task { await viewModel.moveSelected(moves) }
        }

        func deleteSelected(ids: [UUID]) {
            Task { await viewModel.deleteSelected(ids: ids) }
        }

        func editSticky(id: UUID, content: String) {
            Task { await viewModel.editSticky(id: id, content: content) }
        }

        func deleteSticky(id: UUID) {
            Task { await viewModel.deleteSticky(id: id) }
        }

        func copySticky(id: UUID) {
            viewModel.copySticky(id: id)
        }

        func pasteSticky() {
            Task { await viewModel.pasteSticky() }
        }

        func undo() {
            Task { await viewModel.undo() }
        }

        func bringStickyToFront(id: UUID) {
            Task { await viewModel.bringStickyToFront(id: id) }
        }

        func sendStickyToBack(id: UUID) {
            Task { await viewModel.sendStickyToBack(id: id) }
        }

        func openLabelManager(stickyID: UUID) {
            viewModel.openLabelManager(stickyID: stickyID)
        }

        // MARK: Shapes

        func addShape(_ draft: ShapeDraft) {
            guard let cardID = viewModel.selectedCardID else { return }
            Task { await viewModel.addShape(cardID: cardID, draft: draft) }
        }

        func moveShape(id: UUID, worldX: Double, worldY: Double) {
            Task { await viewModel.moveShape(id: id, x: worldX, y: worldY) }
        }

        func resizeShape(id: UUID, worldFrame: CGRect, lineRising: Bool?) {
            Task { await viewModel.resizeShape(id: id, frame: worldFrame, lineRising: lineRising) }
        }

        func selectShape(id: UUID?) {
            viewModel.select(shapeID: id)
        }

        func deleteShape(id: UUID) {
            Task { await viewModel.deleteShape(id: id) }
        }

        func bringShapeToFront(id: UUID) {
            Task { await viewModel.bringShapeToFront(id: id) }
        }

        func sendShapeToBack(id: UUID) {
            Task { await viewModel.sendShapeToBack(id: id) }
        }

        // MARK: Images

        func addImage(worldX: Double, worldY: Double, payload: CanvasImagePayload) {
            guard let cardID = viewModel.selectedCardID else { return }
            Task { await viewModel.addImage(cardID: cardID, x: worldX, y: worldY, payload: payload) }
        }

        func moveImage(id: UUID, worldX: Double, worldY: Double) {
            Task { await viewModel.moveImage(id: id, x: worldX, y: worldY) }
        }

        func resizeImage(id: UUID, worldFrame: CGRect) {
            Task { await viewModel.resizeImage(id: id, frame: worldFrame) }
        }

        func selectImage(id: UUID?) {
            viewModel.select(imageID: id)
        }

        func deleteImage(id: UUID) {
            Task { await viewModel.deleteImage(id: id) }
        }

        func bringImageToFront(id: UUID) {
            Task { await viewModel.bringImageToFront(id: id) }
        }

        func sendImageToBack(id: UUID) {
            Task { await viewModel.sendImageToBack(id: id) }
        }

        func imageData(assetID: UUID) async -> CanvasImageLoad {
            await viewModel.loadImageData(assetID: assetID)
        }

        // MARK: Texts

        func addText(worldX: Double, worldY: Double) {
            guard let cardID = viewModel.selectedCardID else { return }
            Task { await viewModel.addText(cardID: cardID, x: worldX, y: worldY) }
        }

        func copyText(id: UUID) {
            viewModel.copyText(id: id)
        }

        func pasteText() {
            Task { await viewModel.pasteText() }
        }

        func editText(id: UUID, content: String) {
            Task { await viewModel.editText(id: id, content: content) }
        }

        func moveText(id: UUID, worldX: Double, worldY: Double) {
            Task { await viewModel.moveText(id: id, x: worldX, y: worldY) }
        }

        func setTextFrame(id: UUID, worldFrame: CGRect) {
            Task { await viewModel.setTextFrame(id: id, frame: worldFrame) }
        }

        func selectText(id: UUID?) {
            viewModel.select(textID: id)
        }

        func deleteText(id: UUID) {
            Task { await viewModel.deleteText(id: id) }
        }

        func bringTextToFront(id: UUID) {
            Task { await viewModel.bringTextToFront(id: id) }
        }

        func sendTextToBack(id: UUID) {
            Task { await viewModel.sendTextToBack(id: id) }
        }

        func reportImageLoadFailure(assetID: UUID, reason: ImageLoadFailureReason) {
            viewModel.reportImageLoadFailure(assetID: assetID, reason: reason)
        }

        // MARK: Connectors

        func growConnector(_ gesture: ConnectorGrowGesture) {
            guard let cardID = viewModel.selectedCardID else { return }
            Task { await viewModel.addConnector(cardID: cardID, grow: gesture) }
        }

        func selectConnector(id: UUID?) {
            viewModel.select(connectorID: id)
        }

        func reconnectConnector(_ gesture: ConnectorReconnectGesture) {
            // Reconnect resolves the connector by id alone — no card scope needed (unlike grow).
            Task { await viewModel.reconnectConnector(gesture: gesture) }
        }

        func setConnectorWaypoint(id: UUID, offsetX: Double, offsetY: Double) {
            // Resolves the connector by id alone, like reconnect — no card scope needed.
            Task { await viewModel.setConnectorWaypoint(id: id, offsetX: offsetX, offsetY: offsetY) }
        }

        func deleteConnector(id: UUID) {
            Task { await viewModel.deleteConnector(id: id) }
        }
    }
}
