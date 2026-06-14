import AppKit

/// Keeps ordered Markdown lists sequential (1, 2, 3 …) per contiguous list and indent
/// level. Run after every edit so inserting, indenting, outdenting, or deleting an item
/// cascades to the siblings below it. Bullets (`-`/`*`/`+`) are left untouched.
///
/// Performance: `computeEdits` scans every line on each keystroke — O(n) with no
/// visible-range scoping. Fine for card notes (assumed short); revisit for long documents.
@MainActor
enum MarkdownListRenumber {
    static func apply(to textView: NSTextView) {
        guard let storage = textView.textStorage else { return }
        let ns = textView.string as NSString
        let edits = computeEdits(ns)
        guard !edits.isEmpty else { return }

        let caret = textView.selectedRange().location
        storage.beginEditing()
        for edit in edits.reversed() {   // apply back-to-front so earlier offsets stay valid
            storage.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        storage.endEditing()

        var shift = 0
        for edit in edits where NSMaxRange(edit.range) <= caret {
            shift += (edit.replacement as NSString).length - edit.range.length
        }
        let clamped = min(max(0, caret + shift), (textView.string as NSString).length)
        textView.setSelectedRange(NSRange(location: clamped, length: 0))
    }

    /// One renumber replacement: the digit run to overwrite and its new value.
    /// `internal` so the pure, off-by-one-prone numbering logic is unit-testable without
    /// an `NSTextView` (see `MarkdownListRenumberTests`).
    struct Edit: Equatable {
        let range: NSRange
        let replacement: String
    }

    /// Pure core: given the document text, the digit edits needed to make every ordered
    /// list sequential. No `NSTextView` dependency, so it is directly testable.
    static func computeEdits(_ ns: NSString) -> [Edit] {
        var edits: [Edit] = []
        var counters: [Int: Int] = [:]
        var location = 0
        while location < ns.length {
            let lineRange = ns.lineRange(for: NSRange(location: location, length: 0))
            guard lineRange.length > 0 else { break }
            let contentRange = MarkdownListSyntax.trimmedRange(ns, lineRange)
            let line = ns.substring(with: contentRange) as NSString
            advance(&counters, line: line, lineStart: contentRange.location, into: &edits)
            location = NSMaxRange(lineRange)
        }
        return edits
    }

    private static func advance(
        _ counters: inout [Int: Int], line: NSString, lineStart: Int, into edits: inout [Edit]
    ) {
        guard line.length > 0, let match = MarkdownListSyntax.match(line) else {
            counters.removeAll()                                  // blank/non-list line ends every list
            return
        }
        let width = MarkdownListSyntax.leadingWhitespace(line)
        let digits = match.range(at: 3)
        guard digits.location != NSNotFound else {
            counters = counters.filter { $0.key < width }         // a bullet resets ordered runs at ≥ width
            return
        }
        counters = counters.filter { $0.key <= width }            // deeper sublists have ended
        let number = (counters[width] ?? 0) + 1
        counters[width] = number

        guard line.substring(with: digits) != String(number) else { return }
        edits.append(Edit(
            range: NSRange(location: lineStart + digits.location, length: digits.length),
            replacement: String(number)
        ))
    }
}
