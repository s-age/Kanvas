import AppKit

// MARK: - Selection routing + context menu (z-order / delete)
//
// Split into a same-folder extension so the main `CanvasNSView` body stays within the type/file
// length budgets. `selectHit` and the right-click menu both route by item kind (sticky vs shape).

extension CanvasNSView {

    /// Routes a tap-selected item to the matching ViewModel selection (mutually exclusive). Not
    /// file-private: the mouse handlers in the main file call it too.
    func selectHit(_ item: CanvasItem) {
        switch item {
        case .sticky(let sticky): actions?.selectSticky(id: sticky.id)
        case .shape(let shape): actions?.selectShape(id: shape.id)
        case .image(let image): actions?.selectImage(id: image.id)
        case .text(let text): actions?.selectText(id: text.id)
        }
    }

    /// Whether `id` is part of the current selection (drawn with a highlight).
    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    /// Whether `id` is the **only** selected item. Single-only affordances (resize handle, segment
    /// endpoint handles, connector-grow edge handles, label icon) gate on this so they never appear
    /// on a multi-selection — where resize/colour are intentionally unavailable.
    func isSoleSelection(_ id: UUID) -> Bool {
        selectedIDs.count == 1 && selectedIDs.contains(id)
    }

    /// The sole selected item's id, when exactly one is selected — the target of the single-selection
    /// affordances (resize / connector-grow / label icon).
    var soleSelectedID: UUID? {
        selectedIDs.count == 1 ? selectedIDs.first : nil
    }

    /// Every item whose view-space rect intersects the marquee rect `viewRect`. Intersect (not
    /// contain) semantics — an item caught even partially by the rubber-band is selected.
    func itemIDs(inMarquee viewRect: CGRect) -> Set<UUID> {
        var ids: Set<UUID> = []
        for item in items where self.viewRect(for: item).intersects(viewRect) { ids.insert(item.id) }
        return ids
    }

    /// Whether `id` is a shape (vs a sticky), used to route z-order / delete / copy actions.
    /// Not file-private: the keyboard extension (separate file) routes delete/copy through it.
    func isShape(_ id: UUID) -> Bool {
        shapes.contains { $0.id == id }
    }

    /// Whether `id` is an image, used to route z-order / delete actions (and to keep copy
    /// sticky-only). Not file-private: the keyboard extension (separate file) routes through it.
    func isImage(_ id: UUID) -> Bool {
        images.contains { $0.id == id }
    }

    /// Whether `id` is a connector, used to route delete (and to keep copy/z-order sticky-only).
    /// Not file-private: the keyboard extension (separate file) routes delete through it.
    func isConnector(_ id: UUID) -> Bool {
        connectors.contains { $0.id == id }
    }

    /// Whether `id` is a free-text object, used to route z-order / delete actions (and to keep copy
    /// sticky-only). Not file-private: the keyboard extension (separate file) routes through it.
    func isText(_ id: UUID) -> Bool {
        texts.contains { $0.id == id }
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let world = viewToWorld(convert(event.locationInWindow, from: nil))
        guard let hit = item(atWorld: world) else {
            // No sticky/shape under the cursor — offer to delete a connector if one is there.
            guard let connector = connector(atWorld: world) else { return nil }
            actions?.selectConnector(id: connector.id)
            let menu = NSMenu()
            menu.addItem(deleteConnectorMenuItem(id: connector.id))
            return menu
        }
        // The selected item drives delete/z-order; right-clicking also selects so the toolbar and
        // the menu agree on the target.
        selectHit(hit)
        let menu = NSMenu()
        menu.addItem(menuItem("Bring to Front", id: hit.id, action: #selector(bringToFrontAction(_:))))
        menu.addItem(menuItem("Send to Back", id: hit.id, action: #selector(sendToBackAction(_:))))
        menu.addItem(.separator())
        menu.addItem(deleteMenuItem(id: hit.id))
        return menu
    }

    private func menuItem(_ title: String, id: UUID, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.representedObject = id
        return item
    }

    /// The destructive "Delete" item — leading trash glyph, red title, both in the system red.
    private func deleteMenuItem(id: UUID) -> NSMenuItem {
        styledDeleteItem(id: id, action: #selector(deleteAction(_:)))
    }

    /// The connector variant of the destructive "Delete" item (routes to `deleteConnector`).
    func deleteConnectorMenuItem(id: UUID) -> NSMenuItem {
        styledDeleteItem(id: id, action: #selector(deleteConnectorAction(_:)))
    }

    private func styledDeleteItem(id: UUID, action: Selector) -> NSMenuItem {
        let title = "Delete"
        let item = menuItem(title, id: id, action: action)
        item.attributedTitle = NSAttributedString(
            string: title,
            attributes: [.foregroundColor: NSColor.systemRed]
        )
        let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed])
        item.image = NSImage(systemSymbolName: "trash", accessibilityDescription: title)?
            .withSymbolConfiguration(config)
        return item
    }

    @objc fileprivate func bringToFrontAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if isShape(id) {
            actions?.bringShapeToFront(id: id)
        } else if isImage(id) {
            actions?.bringImageToFront(id: id)
        } else if isText(id) {
            actions?.bringTextToFront(id: id)
        } else {
            actions?.bringStickyToFront(id: id)
        }
    }

    @objc fileprivate func sendToBackAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if isShape(id) {
            actions?.sendShapeToBack(id: id)
        } else if isImage(id) {
            actions?.sendImageToBack(id: id)
        } else if isText(id) {
            actions?.sendTextToBack(id: id)
        } else {
            actions?.sendStickyToBack(id: id)
        }
    }

    @objc fileprivate func deleteAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        if isShape(id) {
            actions?.deleteShape(id: id)
        } else if isImage(id) {
            actions?.deleteImage(id: id)
        } else if isText(id) {
            actions?.deleteText(id: id)
        } else {
            actions?.deleteSticky(id: id)
        }
    }

    @objc fileprivate func deleteConnectorAction(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        actions?.deleteConnector(id: id)
    }
}
