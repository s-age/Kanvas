import AppKit
import SwiftUI

/// AppKit-backed Markdown source editor. macOS 15's SwiftUI `TextEditor` renders only
/// plain text, so to style Markdown *as it is typed* we wrap an `NSTextView` and re-apply
/// syntax attributes (`MarkdownHighlighter`) on every edit. This is the single sanctioned
/// AppKit surface in Presentation (see `.swiftlint.yml` `presentation_no_appkit` exclusion).
struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    /// The board's Markdown styling settings (font / heading sizes / colours / monospaced toggle),
    /// or `nil` before the board loads. Drives the resolved `MarkdownTheme`.
    var settings: MarkdownSettingsResponse?
    /// The board's Global appearance settings (background + default text colour), or `nil` before
    /// the board loads. Folded into the resolved `MarkdownTheme` so the editor honours the same
    /// Global colours as the Kanban board.
    var global: GlobalSettingsResponse?
    /// Called when the field loses first-responder focus — the cue to persist.
    var onEndEditing: () -> Void
    /// Saves a dropped/pasted image's PNG bytes as a sidecar asset and returns its id (or `nil` on
    /// failure), so the editor can insert a `kanvas-asset://<id>` reference at the drop point. Bridged
    /// to `BoardViewModel.addMarkdownImage` by `MarkdownEditorView`. The referenced image is *displayed*
    /// by `MarkdownImageGallery` below the editor — not inline here (ticket 04568CD4) — so the text view
    /// neither loads nor renders asset bytes.
    var saveDroppedImage: (CanvasImagePayload) async -> UUID?

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        // Build the scroll view + text view manually so the document view is the
        // `MarkdownEditorTextView` subclass (needed for the `drawBackground` decoration override).
        // `NSTextView.scrollableTextView()` always creates a plain `NSTextView` — calling it on
        // the subclass returns the scroll view but the document view is still `NSTextView`.
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        // Construct with the TextKit 1 stack explicitly via `init(frame:textContainer:)`.
        // `MarkdownDecorationPainter` derives decoration geometry from
        // `NSLayoutManager.enumerateLineFragments`, which requires TextKit 1.
        // The default `NSTextView.init(frame:)` on macOS 13+ creates a TextKit 2 backing
        // and silently downgrades on the first `.layoutManager` access; building the
        // NSTextStorage + NSLayoutManager + NSTextContainer stack here and passing the
        // container directly guarantees TextKit 1 with no downgrade warning.
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width,
                                                         height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)
        let textView = MarkdownEditorTextView(frame: NSRect(origin: .zero, size: contentSize),
                                              textContainer: textContainer)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        // textContainer.widthTracksTextView and containerSize already set during TK1 stack init.
        scrollView.documentView = textView

        textView.delegate = context.coordinator
        // Rich text mode so per-range attributes (headings, bold, code) actually render.
        // Each edit re-runs the highlighter, which resets every range to computed
        // attributes — so any pasted formatting is normalized away on the next keystroke.
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)

        textView.string = text
        let theme = MarkdownTheme(settings: settings, global: global)
        context.coordinator.appliedSettings = settings
        context.coordinator.appliedGlobal = global
        applyTheme(theme, to: textView)
        // Let the text view route image drops back to the coordinator, and accept
        // dragged images/file URLs (mirrors the canvas carve-out's registration).
        textView.imageCoordinator = context.coordinator
        textView.registerForDraggedTypes([.fileURL, .png, .tiff])
        // Inline image references render as plain (highlighted) source text — NOT as drawn
        // `NSTextAttachment`s. The attachment path drove a TextKit-1 layout-hole crash on macOS
        // (`-[NSLayoutManager _fillLayoutHoleAtIndex:]` during `NSTextView.sizeToFit`, ticket
        // 04568CD4) that no amount of layout invalidation could make reliable; the images are now
        // shown crash-free below the editor by `MarkdownImageGallery`. `applyTheme` already applied
        // the highlighter above, so the storage is styled and there is nothing to conceal.
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? MarkdownEditorTextView else { return }
        guard !textView.hasMarkedText() else { return }   // never replace text mid IME composition

        let coordinator = context.coordinator
        // The Coordinator was made once (at `makeCoordinator`) and holds the *original* struct copy.
        // Refresh it each update so delegate callbacks (`textDidChange` → `parent.text`,
        // `textDidEndEditing` → `parent.onEndEditing`) act on the latest binding/closure, not a stale
        // one captured at first render. This is the standard NSViewRepresentable coordinator pattern.
        coordinator.parent = self
        // Rebuild the theme only when settings actually change. `MarkdownTheme.init` allocates
        // several `NSFont`s (incl. an `NSFontManager` italic conversion) and parses colour values,
        // so caching the resolved theme keeps that cost off every keystroke-driven re-render (and
        // off `textDidChange`). A settings change re-styles the whole storage (new fonts/colours)
        // and re-pins the typing/marked attributes — independent of any text change.
        if coordinator.appliedSettings != settings || coordinator.appliedGlobal != global {
            coordinator.appliedSettings = settings
            coordinator.appliedGlobal = global
            let newTheme = MarkdownTheme(settings: settings, global: global)
            applyTheme(newTheme, to: textView)
            // Decorations depend on the theme; invalidate so `drawBackground` picks up new colors.
            textView.invalidateDecorationCache()
            textView.setNeedsDisplay(textView.bounds)
        }
        // Only push an *external* change (e.g. switching cards) into the view — never overwrite while
        // the user is mid-edit, which would reset the cursor. The storage now holds pure source text
        // (no concealed-image attachment glyphs), so a plain string compare is exact.
        if let storage = textView.textStorage, storage.string != text {
            textView.string = text
            // Re-highlight the freshly seeded source (image references render as plain styled text).
            MarkdownHighlighter.apply(to: textView.textStorage, theme: textView.theme)
            textView.invalidateDecorationCache()
            textView.setNeedsDisplay(textView.bounds)
        }
    }

    /// Applies the resolved theme to the view's base font, typing/marked attributes, and the full
    /// storage. Pins typed and IME-composing (marked) text to the base font so an in-progress
    /// Japanese conversion doesn't render at the default (larger) system size.
    @MainActor
    private func applyTheme(_ theme: MarkdownTheme, to textView: MarkdownEditorTextView) {
        textView.font = theme.baseFont
        // Background follows the Global override (or the native editor background when unset),
        // applied to both the text view and its scroll view so the whole pane recolours.
        textView.drawsBackground = true
        textView.backgroundColor = theme.backgroundColor
        textView.enclosingScrollView?.drawsBackground = true
        textView.enclosingScrollView?.backgroundColor = theme.backgroundColor
        let base: [NSAttributedString.Key: Any] = [
            .font: theme.baseFont, .foregroundColor: theme.textColor
        ]
        textView.typingAttributes = base
        textView.markedTextAttributes = base.merging(
            [.underlineStyle: NSUnderlineStyle.single.rawValue]
        ) { current, _ in current }
        textView.theme = theme
        MarkdownHighlighter.apply(to: textView.textStorage, theme: theme)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        /// The owning representable. Refreshed in `updateNSView` (a struct copy is captured at
        /// `makeCoordinator`, so without the refresh the delegate callbacks would write through a
        /// stale `text` binding / `onEndEditing` closure).
        fileprivate var parent: MarkdownTextView
        /// The settings last pushed into the text view — compared in `updateNSView` to detect a
        /// styling change. Rebuilt when either changes; the resolved theme is owned by the text
        /// view (`MarkdownEditorTextView.theme`) so all consumers read the same instance.
        var appliedSettings: MarkdownSettingsResponse?
        /// The Global settings last pushed in — compared alongside `appliedSettings` so a change to
        /// the Global background/text colour also triggers a theme rebuild.
        var appliedGlobal: GlobalSettingsResponse?

        init(_ parent: MarkdownTextView) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? MarkdownEditorTextView else { return }
            // Skip while an IME conversion is in flight — mutating storage or selection
            // would corrupt the marked text. textDidChange fires again on commit.
            guard !textView.hasMarkedText() else { return }
            MarkdownListRenumber.apply(to: textView)   // cascade ordered-list numbers first
            // The storage holds pure source text (no inline-image attachment glyphs — ticket
            // 04568CD4), so the persisted body is just the storage string; the gallery draws images.
            parent.text = textView.string
            // Re-apply syntax highlighting over the edited source (image references stay plain text).
            MarkdownHighlighter.apply(to: textView.textStorage, theme: textView.theme)
            // Invalidate the decoration range cache after every edit — glyph layout may have
            // shifted. `drawBackground` will recompute and redraw.
            textView.invalidateDecorationCache()
            textView.setNeedsDisplay(textView.bounds)
        }

        func textDidEndEditing(_ notification: Notification) {
            parent.onEndEditing()
        }

        /// Saves a dropped image and inserts its `kanvas-asset://<id>` reference at the drop point.
        /// Returns immediately (the save is async); the inserted reference shows as plain styled text
        /// here and as an image in `MarkdownImageGallery` once the body update propagates.
        func handleImageDrop(payload: CanvasImagePayload, at characterIndex: Int, in textView: NSTextView) {
            let save = parent.saveDroppedImage
            Task { @MainActor [weak textView] in
                guard let assetID = await save(payload), let textView else { return }
                let reference = MarkdownImageReference.markdown(for: assetID)
                // Surround with newlines so the reference sits on its own line (reads cleanly as
                // source). Insert at the drop point.
                let insertion = "\n\(reference)\n"
                let clamped = min(max(0, characterIndex), textView.textStorage?.length ?? 0)
                textView.insertText(insertion, replacementRange: NSRange(location: clamped, length: 0))
                // insertText drives textDidChange → the body binding updates and the gallery refreshes.
            }
        }

        /// Intercept Return / Tab / Shift+Tab for Markdown list editing; defer everything else.
        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                return MarkdownListContinuation.handleNewline(in: textView)
            case #selector(NSResponder.insertTab(_:)):
                return MarkdownListContinuation.handleTab(in: textView)
            case #selector(NSResponder.insertBacktab(_:)):
                return MarkdownListContinuation.handleBacktab(in: textView)
            default:
                return false
            }
        }
    }
}

// MARK: - Custom NSTextView subclass for block decoration drawing

/// `NSTextView` subclass that draws block-level Markdown decorations (fenced code block background
/// and blockquote left border bar) in `drawBackground(in:)`, behind the text layer. The decoration
/// geometry is derived from the TextKit 1 layout manager.  `theme` is the single owner of the
/// resolved `MarkdownTheme`; `MarkdownTextView.applyTheme(_:to:)` writes it and calls
/// `invalidateDecorationCache()` + `setNeedsDisplay`.
@MainActor
final class MarkdownEditorTextView: NSTextView {
    /// The current resolved theme — single source of truth; read by the Coordinator and the
    /// decoration painter.  Set via `applyTheme(_:to:)` in the NSViewRepresentable wrapper.
    var theme: MarkdownTheme = .default

    /// Routes image drops to the coordinator (which saves the asset + inserts the reference). Weak —
    /// the coordinator owns no strong claim to its document view (avoids a retain cycle).
    weak var imageCoordinator: MarkdownTextView.Coordinator?

    /// Accept an image drop when the drag carries an image object (in-app / browser) or an image file
    /// URL (Finder) — mirrors the canvas carve-out's acceptance test.
    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsImageDrag(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        acceptsImageDrag(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let coordinator = imageCoordinator,
              let image = droppedImage(from: sender),
              let payload = ImagePNGEncoder.pngPayload(from: image) else {
            return super.performDragOperation(sender)
        }
        // The drop lands at the nearest character to the cursor location (view space).
        let point = convert(sender.draggingLocation, from: nil)
        let index = characterIndexForInsertion(at: point)
        coordinator.handleImageDrop(
            payload: CanvasImagePayload(pngData: payload.data,
                                        naturalWidth: payload.width,
                                        naturalHeight: payload.height),
            at: index, in: self
        )
        return true
    }

    /// ⌘V paste: if the general pasteboard carries an image (screenshot, copied picture, browser
    /// image), import it as an inline asset at the caret — mirroring the canvas carve-out's
    /// `pasteImageFromPasteboard`. The downstream is identical to the drop path (save asset → insert
    /// `kanvas-asset://<id>` reference → shown in the gallery), so this only intercepts the paste before
    /// `NSTextView` would otherwise drop the image bytes (it can't render them) or paste nothing.
    /// Falls through to the normal text paste when the pasteboard holds no image.
    override func paste(_ sender: Any?) {
        if pasteImageIfPresent() { return }
        super.paste(sender)
    }

    /// Reads an image off the general pasteboard, encodes it to PNG, and routes it through the same
    /// `handleImageDrop` save-and-insert path the drop uses — inserting at the current caret/selection.
    /// Returns `true` when an image was found and handled, `false` when the pasteboard carries no image
    /// (so the caller falls back to the standard text paste).
    private func pasteImageIfPresent() -> Bool {
        guard let coordinator = imageCoordinator,
              let image = (NSPasteboard.general.readObjects(forClasses: [NSImage.self]) as? [NSImage])?.first,
              let payload = ImagePNGEncoder.pngPayload(from: image) else { return false }
        // Insert at the caret (the selection start). handleImageDrop inserts a zero-length range, so
        // a non-empty selection is kept and the image lands before it — matching the drop path, which
        // also inserts at a point rather than replacing a range.
        let index = selectedRange().location
        coordinator.handleImageDrop(
            payload: CanvasImagePayload(pngData: payload.data,
                                        naturalWidth: payload.width,
                                        naturalHeight: payload.height),
            at: index, in: self
        )
        return true
    }

    private func acceptsImageDrag(_ sender: any NSDraggingInfo) -> Bool {
        let pasteboard = sender.draggingPasteboard
        if pasteboard.canReadObject(forClasses: [NSImage.self], options: nil) { return true }
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: Self.imageURLReadingOptions)
    }

    /// The dropped image: an `NSImage` object when present (in-app / browser), else loaded from a
    /// dropped image file URL (Finder) — `nil` when the drag carries no image.
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

    /// Restricts dropped file URLs to image files so a non-image file drop is not accepted (mirrors
    /// the canvas carve-out's option set).
    private static let imageURLReadingOptions: [NSPasteboard.ReadingOptionKey: Any] = [
        .urlReadingFileURLsOnly: true,
        .urlReadingContentsConformToTypes: NSImage.imageTypes,
    ]

    /// Cached decoration ranges for the current text + theme. Recomputed lazily on the next
    /// `drawBackground` call after `invalidateDecorationCache()` clears it.  Caching avoids two
    /// full-document regex sweeps on every scroll, selection change, and caret blink.
    ///
    /// **IME tradeoff:** edits during IME composition do not invalidate the cache — the
    /// `Coordinator.textDidChange` guard (`hasMarkedText()`) skips the invalidation while marked
    /// text is active — so decorations can be briefly stale mid-composition and snap back on commit.
    /// This is intentional and consistent with the same guard skipping syntax highlighting.
    private var cachedDecorationRanges: [DecorationRange]?

    /// Marks the decoration cache stale. Call after every text change or theme update.
    func invalidateDecorationCache() {
        cachedDecorationRanges = nil
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        // Draw block decorations (code-block background, quote border bar) after the view's own
        // background fill so they are not overdrawn, but before the text glyph layer.
        if cachedDecorationRanges == nil {
            cachedDecorationRanges = MarkdownDecorationPainter.decorationRanges(in: string)
        }
        MarkdownDecorationPainter.drawDecorations(
            in: self,
            decorations: cachedDecorationRanges ?? [],
            dirtyRect: rect,
            theme: theme
        )
    }
}
