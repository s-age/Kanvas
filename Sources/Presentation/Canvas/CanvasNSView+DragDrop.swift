import AppKit

// MARK: - Drag-and-drop (palette creation + image import)

/// The canvas is a drop destination for two kinds of drag:
/// - the left-edge `StickyPaletteView` swatches, which carry a `"preset:<uuid>"` / `"shape:<kind>"`
///   string payload — dropping one creates that item centred on the drop point;
/// - an image file (from Finder) or a picture (from another app), which drops as a canvas image.
/// Registration for the accepted types happens in `CanvasNSView`'s init.
extension CanvasNSView {

    /// Prefix on a sticky-preset palette drag payload (mirrors `ShapeRegistry`'s `"shape:"`).
    static let stickyPresetPayloadPrefix = "preset:"
    /// The free-text palette item's drag payload (a single token — texts carry no preset/kind).
    static let textPayload = "text"

    /// Decodes a `"preset:<uuid>"` palette payload to the preset id, or `nil` for any other string.
    static func stickyPresetID(from raw: String) -> UUID? {
        guard raw.hasPrefix(stickyPresetPayloadPrefix) else { return nil }
        return UUID(uuidString: String(raw.dropFirst(stickyPresetPayloadPrefix.count)))
    }

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .copy : []
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        // The drop point (view space) becomes the new item's centre in world space, snapped to the
        // grid when grid-snap is enabled.
        let world = snap(viewToWorld(convert(sender.draggingLocation, from: nil)))

        // A `"shape:<kind>"` palette payload creates a shape; a `"preset:<uuid>"` payload creates a
        // sticky from that preset. Both are checked before image content (a palette drag carries no
        // image).
        if let raw = payload(from: sender) {
            if let definition = ShapeRegistry.definition(forDragPayload: raw) {
                actions?.addShape(ShapeDraft(
                    worldX: Double(world.x), worldY: Double(world.y),
                    kind: definition.kind, topology: definition.topology,
                    defaultWidth: definition.defaultWidth, defaultHeight: definition.defaultHeight
                ))
                return true
            }
            if let presetID = Self.stickyPresetID(from: raw) {
                actions?.addSticky(worldX: Double(world.x), worldY: Double(world.y), presetID: presetID)
                return true
            }
            if raw == Self.textPayload {
                actions?.addText(worldX: Double(world.x), worldY: Double(world.y))
                return true
            }
        }

        // An image file / picture drops as a canvas image at the drop point.
        if let image = droppedImage(from: sender), let payload = pngPayload(from: image) {
            actions?.addImage(worldX: Double(world.x), worldY: Double(world.y),
                              payload: CanvasImagePayload(pngData: payload.data,
                                                          naturalWidth: payload.width,
                                                          naturalHeight: payload.height))
            return true
        }
        return false
    }

    /// Whether the drag carries something the canvas can place: a palette payload, an image object
    /// (in-app / browser drag), or an image **file URL** (the shape a Finder drag actually takes —
    /// `NSImage` does not claim a bare file URL without the content-type reading option, which is
    /// why a plain `canReadObject([NSImage.self])` rejected Finder drops).
    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        if let raw = payload(from: sender),
           ShapeRegistry.definition(forDragPayload: raw) != nil || Self.stickyPresetID(from: raw) != nil
            || raw == Self.textPayload {
            return true
        }
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: Self.imageURLReadingOptions)
    }

    /// The raw pasteboard string carried by a palette drag, or `nil` for any other drag content.
    private func payload(from sender: any NSDraggingInfo) -> String? {
        sender.draggingPasteboard.readObjects(forClasses: [NSString.self])?.first as? String
    }

    /// The dropped image: an `NSImage` object when present (in-app / browser drag), else loaded
    /// from a dropped image **file URL** (Finder drag) — `nil` when the drag carries no image.
    private func droppedImage(from sender: any NSDraggingInfo) -> NSImage? {
        let pasteboard = sender.draggingPasteboard
        if let image = (pasteboard.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first {
            return image
        }
        guard let url = (pasteboard.readObjects(forClasses: [NSURL.self],
                                                options: Self.imageURLReadingOptions) as? [URL])?.first
        else { return nil }
        return NSImage(contentsOf: url)
    }

    /// Restricts dropped file URLs to image files, so a non-image file drop is not accepted.
    private static let imageURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: NSImage.imageTypes,
    ]
}
