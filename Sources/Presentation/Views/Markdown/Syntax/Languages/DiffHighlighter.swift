import Foundation

/// Unified-diff highlighter. Line-oriented (not regex-rule based) because each diff line's *first*
/// character classifies the whole line: `+` added, `-` removed, `@@` hunk header, `diff`/`index`/
/// `+++`/`---` meta. The `diffAdded` / `diffRemoved` tokens additionally drive the full-width line
/// background painted by `MarkdownDecorationPainter` (an attribute background can only paint glyph
/// width, so the line fill is a painter pass, not a `.backgroundColor`).
struct DiffHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["diff", "patch"]

    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken] {
        let ns = text as NSString
        var tokens: [CodeToken] = []
        var index = nsRange.location
        let end = NSMaxRange(nsRange)

        while index < end {
            let lineRange = ns.lineRange(for: NSRange(location: index, length: 0))
            // Content range excluding the trailing newline so the token does not span lines.
            let contentLength = trimmedLineLength(ns, lineRange)
            let contentRange = NSRange(location: lineRange.location, length: contentLength)
            if let kind = classify(ns, contentRange) {
                tokens.append(CodeToken(range: contentRange, kind: kind))
            }
            let next = NSMaxRange(lineRange)
            if next <= index { break }   // guard against zero-length line ranges
            index = next
        }
        return tokens
    }

    /// Length of the line excluding a trailing `\n` / `\r\n`.
    private func trimmedLineLength(_ ns: NSString, _ lineRange: NSRange) -> Int {
        var length = lineRange.length
        let lineEnd = NSMaxRange(lineRange)
        if length > 0, ns.character(at: lineEnd - 1) == 0x0A { length -= 1 }   // \n
        if length > 0, ns.character(at: lineRange.location + length - 1) == 0x0D { length -= 1 }  // \r
        return length
    }

    /// Classifies a diff line by its prefix. Meta lines (`+++`/`---`/`diff`/`index`) are checked
    /// before the single-char `+`/`-` tests so a `+++` header is meta, not an added line.
    private func classify(_ ns: NSString, _ range: NSRange) -> CodeTokenKind? {
        guard range.length > 0 else { return nil }
        let line = ns.substring(with: range)
        if line.hasPrefix("@@") { return .diffHunkHeader }
        if line.hasPrefix("+++") || line.hasPrefix("---")
            || line.hasPrefix("diff ") || line.hasPrefix("index ") { return .diffMeta }
        if line.hasPrefix("+") { return .diffAdded }
        if line.hasPrefix("-") { return .diffRemoved }
        return nil
    }
}
