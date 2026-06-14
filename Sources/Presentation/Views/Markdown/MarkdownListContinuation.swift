import AppKit

/// Keyboard behaviors for Markdown lists inside the editor:
/// - **Return** continues the list (same bullet / next ordinal); on an *empty* item it
///   outdents one level, and exits the list once it reaches the left margin.
/// - **Tab** indents the current item one level (child list).
/// - **Shift+Tab** outdents the current item one level (child → parent).
///
/// Ordinal numbering is *not* decided here — `MarkdownListRenumber` re-sequences every
/// ordered list after each edit, so these handlers only move text and indentation.
@MainActor
enum MarkdownListContinuation {
    /// One nesting level. Four spaces nests cleanly under any marker (`-`/`*`/`+`/`1.`).
    private static let indentLen = 4

    // MARK: - Return

    /// Returns `true` when it handled the newline, `false` to let `NSTextView` insert a plain one.
    static func handleNewline(in textView: NSTextView) -> Bool {
        let ns = textView.string as NSString
        let range = MarkdownListSyntax.contentRange(ns, caret: textView.selectedRange().location)
        let line = ns.substring(with: range) as NSString
        guard let match = MarkdownListSyntax.match(line) else { return false }

        let indent = line.substring(with: match.range(at: 1))
        let spacing = line.substring(with: match.range(at: 4))
        let content = line.substring(with: match.range(at: 5))

        // Detect task-list item: reuse the compiled static pattern from MarkdownHighlighter.
        let contentNS = content as NSString
        let taskMatch = MarkdownHighlighter.Patterns.taskCheckbox.firstMatch(
            in: content,
            range: NSRange(location: 0, length: contentNS.length)
        )
        let isTaskItem = taskMatch != nil

        // An empty item for task lists means the content after the checkbox is empty,
        // not the whole content string (which includes the checkbox itself).
        var effectiveEmpty = content.isEmpty
        if isTaskItem, let tm = taskMatch {
            let afterCheckbox = contentNS.substring(from: NSMaxRange(tm.range))
            effectiveEmpty = afterCheckbox.trimmingCharacters(in: .whitespaces).isEmpty
        }

        if effectiveEmpty {
            return outdentEmptyItem(textView, line: line, range: range, hasIndent: !indent.isEmpty)
        }

        let next: String
        if isTaskItem {
            // Continue with an unchecked task item; `nextMarker` handles both bullet and ordinal
            // markers — no need for a separate isBulletMarker check.
            let markerNext = nextMarker(line, marker: match.range(at: 2), digits: match.range(at: 3))
            next = "\(markerNext)\(spacing)[ ] "
        } else {
            next = nextMarker(line, marker: match.range(at: 2), digits: match.range(at: 3)) + spacing
        }
        textView.insertText("\n\(indent)\(next)", replacementRange: textView.selectedRange())
        return true
    }

    /// Empty item: outdent one level if nested, otherwise wipe the marker and leave the list.
    private static func outdentEmptyItem(
        _ textView: NSTextView, line: NSString, range: NSRange, hasIndent: Bool
    ) -> Bool {
        guard hasIndent else {
            textView.insertText("", replacementRange: range)
            return true
        }
        let removed = min(indentLen, MarkdownListSyntax.leadingWhitespace(line))
        textView.insertText("", replacementRange: NSRange(location: range.location, length: removed))
        textView.setSelectedRange(NSRange(location: range.location + range.length - removed, length: 0))
        return true
    }

    // MARK: - Tab / Shift+Tab

    static func handleTab(in textView: NSTextView) -> Bool {
        guard let ctx = listContext(textView) else { return false }   // defer plain Tab off-list
        return reindent(textView, ctx, indenting: true)
    }

    static func handleBacktab(in textView: NSTextView) -> Bool {
        if let ctx = listContext(textView) {
            return reindent(textView, ctx, indenting: false)
        }
        return plainOutdent(textView)
    }

    private static func reindent(_ textView: NSTextView, _ ctx: ListContext, indenting: Bool) -> Bool {
        let currentWidth = MarkdownListSyntax.leadingWhitespace(ctx.line)
        let newWidth: Int
        if indenting {
            newWidth = currentWidth + indentLen
        } else {
            guard currentWidth > 0 else { return false }
            newWidth = max(0, currentWidth - indentLen)
        }
        let indent = String(repeating: " ", count: newWidth)
        let marker = ctx.line.substring(with: ctx.match.range(at: 2))
        let spacing = ctx.line.substring(with: ctx.match.range(at: 4))
        let content = ctx.line.substring(with: ctx.match.range(at: 5))
        let prefix = indent + marker + spacing

        textView.insertText(prefix + content, replacementRange: ctx.range)
        let shift = (prefix as NSString).length - ctx.match.range(at: 5).location
        let caret = max(ctx.range.location, ctx.selection.location + shift)
        textView.setSelectedRange(NSRange(location: caret, length: ctx.selection.length))
        return true
    }

    /// Non-list indented line: strip one indent unit so Shift+Tab still does something useful.
    private static func plainOutdent(_ textView: NSTextView) -> Bool {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let range = MarkdownListSyntax.contentRange(ns, caret: selection.location)
        let line = ns.substring(with: range) as NSString
        let removed = min(indentLen, MarkdownListSyntax.leadingWhitespace(line))
        guard removed > 0 else { return false }

        textView.insertText("", replacementRange: NSRange(location: range.location, length: removed))
        let caret = max(range.location, selection.location - removed)
        textView.setSelectedRange(NSRange(location: caret, length: selection.length))
        return true
    }

    // MARK: - Helpers

    private struct ListContext {
        let line: NSString
        let range: NSRange
        let match: NSTextCheckingResult
        let selection: NSRange
    }

    private static func listContext(_ textView: NSTextView) -> ListContext? {
        let ns = textView.string as NSString
        let selection = textView.selectedRange()
        let range = MarkdownListSyntax.contentRange(ns, caret: selection.location)
        let line = ns.substring(with: range) as NSString
        guard let match = MarkdownListSyntax.match(line) else { return nil }
        return ListContext(line: line, range: range, match: match, selection: selection)
    }

    private static func nextMarker(_ line: NSString, marker: NSRange, digits: NSRange) -> String {
        if digits.location != NSNotFound, let value = Int(line.substring(with: digits)) { return "\(value + 1)." }
        return line.substring(with: marker)
    }
}
