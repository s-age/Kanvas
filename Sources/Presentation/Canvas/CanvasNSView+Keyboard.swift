import AppKit

// MARK: - Keyboard shortcuts

extension CanvasNSView {

    override func keyDown(with event: NSEvent) {
        // Text editing routes its own keys to the overlaid editor (it is first responder then),
        // so canvas shortcuts only apply when not editing.
        guard editingID == nil else { return super.keyDown(with: event) }

        // ⌘Z reverts the last board change (move / resize / edit / create / delete). Shift+⌘Z
        // is conventionally redo, which is unsupported — let it fall through.
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift),
           event.charactersIgnoringModifiers == "z" {
            actions?.undo()
            return
        }

        // ⌘C copies the selected sticky or free-text into the ViewModel's paste buffer; ⌘V pastes
        // either a system-pasteboard image (screenshot, copied picture) as a canvas image, or — when
        // there is no image — the internal sticky/text buffer (whichever was last copied; they are
        // mutually exclusive). Copy is sticky/text-only (shapes/images have no paste buffer).
        if event.modifierFlags.contains(.command),
           !event.modifierFlags.contains(.shift) {
            if event.charactersIgnoringModifiers == "c", let id = soleSelectedID {
                if isText(id) {
                    actions?.copyText(id: id)
                    return
                }
                if !isShape(id), !isConnector(id), !isImage(id) {
                    actions?.copySticky(id: id)
                    return
                }
            }
            if event.charactersIgnoringModifiers == "v" {
                if pasteImageFromPasteboard() { return }
                actions?.pasteText()
                actions?.pasteSticky()
                return
            }
        }

        // Delete / Forward-delete removes every selected item (stickies, shapes, images, connectors).
        // One id is the common case; a multi-selection deletes as a group.
        let deleteKeyCodes: Set<UInt16> = [51, 117]  // delete (⌫), forward-delete (⌦)
        if !selectedIDs.isEmpty, deleteKeyCodes.contains(event.keyCode) {
            actions?.deleteSelected(ids: Array(selectedIDs))
            return
        }
        super.keyDown(with: event)
    }

    /// Reads an image off the general pasteboard, encodes it to PNG, and asks the canvas to add it
    /// at the viewport centre. Returns `true` when an image was found and handled, `false` when the
    /// pasteboard carries no image (so the caller falls back to the sticky paste buffer).
    func pasteImageFromPasteboard() -> Bool {
        guard let cardImage = NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage],
              let image = cardImage.first,
              let payload = pngPayload(from: image) else { return false }
        let centre = viewToWorld(CGPoint(x: bounds.midX, y: bounds.midY))
        actions?.addImage(worldX: Double(centre.x), worldY: Double(centre.y),
                          payload: CanvasImagePayload(pngData: payload.data,
                                                      naturalWidth: payload.width,
                                                      naturalHeight: payload.height))
        return true
    }

    /// Encodes an `NSImage` to PNG (bytes + possibly-capped pixel dimensions, used to fit the initial
    /// on-canvas size and record the aspect ratio). Delegates to the shared `ImagePNGEncoder` so the
    /// canvas and the Markdown editor downscale + encode identically.
    func pngPayload(from image: NSImage) -> (data: Data, width: Double, height: Double)? {
        ImagePNGEncoder.pngPayload(from: image)
    }
}
