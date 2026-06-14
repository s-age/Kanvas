import AppKit

// MARK: - Inline text editing
//
// The overlaid `NSTextView` editor shown on double-click. Split into a same-folder extension so the
// `CanvasNSView` body stays within the file-length budget; it drives the class's `editingID` /
// `editor` state (intentionally not file-scoped for this reason).

extension CanvasNSView {

    /// Overlays the editor on `sticky`, pre-filled with its raw content (a task sticky's
    /// "☑︎ title" prefix is display-only and not editable here).
    func beginEditing(_ sticky: StickyResponse) {
        let padding = 8 * scale
        let frame = viewRect(for: sticky).insetBy(dx: padding, dy: padding)
        guard frame.width > 0, frame.height > 0 else { return }

        editingID = sticky.id
        editor.frame = frame
        editor.font = NSFont.systemFont(ofSize: sticky.fontSize * scale)
        editor.textColor = effectiveTextColor(for: sticky)
        editor.backgroundColor = flattenedFill(for: sticky)  // keep the sticky's background
        editor.string = sticky.content
        editor.isHidden = false
        if editor.superview == nil { addSubview(editor) }
        needsDisplay = true  // hide the underlying drawn text behind the editor

        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: (sticky.content as NSString).length))
    }

    /// Overlays the editor on a free-text object, pre-filled with its content. A free-text object has
    /// no background, so the editor draws on the canvas background (unlike a sticky, whose editor
    /// keeps the sticky's fill).
    func beginEditingText(_ text: TextResponse) {
        let padding = 4 * scale
        let frame = viewRect(for: .text(text)).insetBy(dx: padding, dy: padding)
        guard frame.width > 0, frame.height > 0 else { return }

        editingID = text.id
        editor.frame = frame
        editor.font = NSFont.systemFont(ofSize: text.fontSize * scale)
        editor.textColor = NSColor(hex: text.textColorHex)
        editor.backgroundColor = canvasBackgroundColor
        editor.string = text.content
        editor.isHidden = false
        if editor.superview == nil { addSubview(editor) }
        needsDisplay = true  // hide the underlying drawn text behind the editor

        window?.makeFirstResponder(editor)
        editor.setSelectedRange(NSRange(location: 0, length: (text.content as NSString).length))
    }

    /// Begins inline editing on a double-clicked item when it carries editable text (a sticky or a
    /// free-text object), returning whether it did. Shapes/images have no text, so they fall through
    /// to normal select/drag. Kept in this extension so the `mouseDown` body stays small.
    func beginEditingIfTextual(_ item: CanvasItem) -> Bool {
        if let sticky = item.stickyValue { beginEditing(sticky); return true }
        if let text = item.textValue { beginEditingText(text); return true }
        return false
    }

    /// Begins inline editing on the text with `id` if it is present on the canvas. Returns whether it
    /// did — the representable uses this to fire the "edit a just-dropped text" request exactly once,
    /// retrying on the next `update` until the new text arrives in `texts`.
    func beginEditingTextIfPresent(id: UUID) -> Bool {
        guard let text = texts.first(where: { $0.id == id }) else { return false }
        beginEditingText(text)
        return true
    }

    /// Persists the in-progress edit (if any) and tears down the editor. Idempotent — safe to
    /// call from pan/zoom, an outside click, or `textDidEndEditing`. Routes by the edited element's
    /// kind: a free-text object's edit goes to `editText` (an empty body auto-deletes it in the
    /// domain), a sticky's to `editSticky`.
    func commitEditing() {
        guard let id = editingID else { return }
        let content = editor.string
        editingID = nil
        editor.isHidden = true
        editor.removeFromSuperview()
        needsDisplay = true
        if let text = texts.first(where: { $0.id == id }) {
            // Persist even when blank — an empty body deletes the text object (domain rule, 決め事 2).
            // A palette-dropped text starts empty and is persisted before editing; if it is dismissed
            // without typing, content still equals the stored "" and the unchanged guard would skip
            // the edit, leaving an invisible orphan. So force the edit when the trimmed body is empty
            // (lets the domain transform delete it); otherwise skip only when genuinely unchanged.
            let trimmedIsEmpty = content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard trimmedIsEmpty || text.content != content else { return }
            actions?.editText(id: id, content: content)
            return
        }
        // Skip the persist round-trip when the sticky text is unchanged.
        guard stickies.first(where: { $0.id == id })?.content != content else { return }
        actions?.editSticky(id: id, content: content)
    }

    func textDidEndEditing(_ notification: Notification) {
        commitEditing()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        // Enter or Escape ends editing (commit on resign). Shift+Enter maps to
        // insertNewlineIgnoringFieldEditor:, which is not intercepted → inserts a newline.
        // (During IME composition Enter confirms the candidate and never reaches here.)
        if commandSelector == #selector(cancelOperation(_:))
            || commandSelector == #selector(NSStandardKeyBindingResponding.insertNewline(_:)) {
            window?.makeFirstResponder(self)
            return true
        }
        return false
    }
}
