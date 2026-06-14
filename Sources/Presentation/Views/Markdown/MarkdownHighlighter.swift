import AppKit

extension NSAttributedString.Key {
    /// Marks a diff line (`+`/`-`) for the full-width line-background decoration painted by
    /// `MarkdownDecorationPainter`. Value is a `DiffLineKind`. An attribute `.backgroundColor` can
    /// only paint glyph width, so the line fill is a painter pass keyed off this attribute.
    static let diffLineKind = NSAttributedString.Key("kanvas.diffLineKind")
}

/// The kind of diff line carried by the `.diffLineKind` attribute, consumed by the decoration
/// painter to choose the line-background colour.
enum DiffLineKind: Equatable, Sendable {
    case added
    case removed
}

/// Re-applies Markdown syntax styling to an `NSTextStorage` after every edit.
/// Markers stay visible (source-mode highlighting, à la Obsidian/Bear) — styling is
/// layered on top of the raw text rather than hiding the syntax.
///
/// Pass ordering matters:
/// 1. Fenced code blocks are resolved first to build an exclusion list; all other passes
///    skip ranges that overlap a code block.
/// 2. Bold-italic (`***x***`) runs before bold and italic so the tighter pattern wins.
/// 3. Images run before links so `![alt](url)` is not double-styled by the link pass.
/// 4. Autolinks run last so already-attributed `[text](url)` regions are not re-styled.
///
/// Performance: each call resets attributes over the whole storage and runs every regex
/// pass over the full text — O(n) per keystroke with no visible-range scoping. This is
/// fine for card notes (assumed short); a long document would show input lag and should
/// move to a visible-range / changed-paragraph scope before that becomes a problem.
///
/// `@MainActor`-isolated to match `MarkdownTheme`'s `NSFont`/`NSColor` constants and the
/// `NSTextStorage` it mutates; the only callers are main-actor `NSTextView` hooks.
@MainActor
enum MarkdownHighlighter {
    static func apply(to storage: NSTextStorage?, theme: MarkdownTheme) {
        guard let storage else { return }
        let str = storage.string

        storage.beginEditing()
        // Establish base paragraph style (line spacing) for all lines before any per-construct
        // pass runs, so non-list / non-heading lines also receive the body line spacing.
        let baseParagraphStyle = makeBaseParagraphStyle(theme: theme)
        storage.setAttributes(
            [.font: theme.baseFont, .foregroundColor: theme.textColor,
             .paragraphStyle: baseParagraphStyle],
            range: fullRange(str)
        )

        // Resolve fenced code blocks first — other passes must skip these ranges.
        let codeBlocks = fencedCodeBlocks(in: str)
        let excluded = codeBlocks.map(\.blockRange)
        styleFencedCodeBlocks(storage, in: str, ranges: excluded, theme: theme)
        // Per-language syntax colouring layered on top of the mono+codeColor base.
        styleCodeBlockSyntax(storage, in: str, blocks: codeBlocks, theme: theme)

        styleHeadings(storage, in: str, excluding: excluded, theme: theme)
        styleInlineCode(storage, in: str, excluding: excluded, theme: theme)
        // Bold-italic runs first and its ranges are excluded from the plain bold/italic passes
        // so that `***x***` is not partially overwritten by the bold pass on the inner `**x**`.
        var boldItalicRanges: [NSRange] = []
        eachMatch(of: Patterns.boldItalic, in: str, excluding: excluded) { range in
            storage.addAttribute(.font, value: theme.boldItalicFont, range: range)
            boldItalicRanges.append(range)
        }
        let excludedPlusBoldItalic = excluded + boldItalicRanges
        eachMatch(of: Patterns.bold, in: str, excluding: excludedPlusBoldItalic) { range in
            storage.addAttribute(.font, value: theme.boldFont, range: range)
        }
        eachMatch(of: Patterns.italic, in: str, excluding: excludedPlusBoldItalic) { range in
            storage.addAttribute(.font, value: theme.italicFont, range: range)
        }
        styleStrikethrough(storage, in: str, excluding: excluded, theme: theme)
        styleLists(storage, in: str, excluding: excluded, theme: theme)
        styleQuotes(storage, in: str, excluding: excluded, theme: theme)
        styleHorizontalRules(storage, in: str, excluding: excluded, theme: theme)
        styleImages(storage, in: str, excluding: excluded, theme: theme)
        styleLinks(storage, in: str, excluding: excluded, theme: theme)
        styleAutolinks(storage, in: str, excluding: excluded, theme: theme)
        styleTables(storage, in: str, excluding: excluded, theme: theme)
        // Paragraph styling pass — must run after colour/font passes so it can read the font
        // already applied to each line (for accurate prefix-width measurement on list lines).
        styleParagraphs(storage, in: str, excluding: excluded, theme: theme)

        storage.endEditing()
    }

    /// Returns a base `NSParagraphStyle` carrying only `lineSpacing`, applied to every line by the
    /// `setAttributes` reset at the top of `apply`. The paragraph styling pass replaces this on
    /// list, heading, and quote lines with richer per-construct styles that also carry lineSpacing.
    static func makeBaseParagraphStyle(theme: MarkdownTheme) -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = theme.lineSpacing
        return style
    }


    // MARK: - Fenced code block range resolution

    /// Returns the `NSRange`s of every fenced code block in `str`, including unterminated
    /// blocks (which extend from their opening fence to the end of text).
    /// These ranges are used by every other pass to skip styling inside code blocks.
    /// Thin wrapper over `fencedCodeBlocks(in:)` (`MarkdownHighlighter+CodeBlocks.swift`),
    /// preserving the original `[NSRange]` contract for callers that only need the exclusion list
    /// (e.g. `MarkdownDecorationPainter`).
    static func fencedCodeBlockRanges(in str: String) -> [NSRange] {
        fencedCodeBlocks(in: str).map(\.blockRange)
    }

    // MARK: - Helpers

    /// Returns `true` when `range` overlaps any range in `excluded`.
    static func intersects(_ range: NSRange, with excluded: [NSRange]) -> Bool {
        for ex in excluded where range.location < NSMaxRange(ex) && NSMaxRange(range) > ex.location {
            return true
        }
        return false
    }

    static func fullRange(_ str: String) -> NSRange {
        NSRange(location: 0, length: (str as NSString).length)
    }

    /// Returns `true` when `trimmedLine` matches the horizontal-rule pattern.
    /// Shared by `styleLists` and `styleParagraphs` to exclude HR-looking lines from list indent.
    static func isHorizontalRuleLine(_ trimmedLine: String) -> Bool {
        let len = (trimmedLine as NSString).length
        return Patterns.horizontalRule.firstMatch(in: trimmedLine,
                                                  range: NSRange(location: 0, length: len)) != nil
    }

    /// Enumerate all non-excluded matches of `pattern` and call `apply` for each.
    static func eachMatch(
        of pattern: NSRegularExpression, in str: String,
        excluding excluded: [NSRange], apply: (NSRange) -> Void
    ) {
        pattern.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let range = match?.range, !intersects(range, with: excluded) else { return }
            apply(range)
        }
    }

    // MARK: - Patterns

    enum Patterns {
        // Headings.
        static let heading = regex("^(#{1,6})\\s+.*$")

        // Emphasis — bold-italic must run before bold/italic.
        static let boldItalic = regex("\\*{3}[^*\\n]+\\*{3}|_{3}[^_\\n]+_{3}")
        static let bold = regex("\\*\\*(?!\\*)[^*\\n]+(?<!\\*)\\*\\*|__(?!_)[^_\\n]+(?<!_)__")
        static let italic = regex("(?<![*_])[*_][^*_\\n]+[*_](?![*_])")

        // Inline code (backtick spans).
        static let inlineCode = regex("`[^`\\n]+`")

        // Strikethrough: group 1 = open `~~`, group 2 = content, group 3 = close `~~`.
        static let strikethrough = regex("(~~)([^~\\n]+)(~~)")

        // Lists — generic bullet/ordered marker.
        static let listMarker = regex("^[ \\t]*([-*+]|\\d+\\.)[ \\t]+")

        // Task-list checkbox: `[ ]` or `[x]` / `[X]`, at the start of after-marker text.
        static let taskCheckbox = StaticRegex.compile("^\\[([ xX])\\][ \\t]?")

        // Blockquotes.
        static let quote = regex("^[ \\t]*>[ \\t]?.*$")

        // Horizontal rules: 3+ of `-`, `*`, or `_`, optionally space-separated, alone on line.
        static let horizontalRule = regex(
            "^[ \\t]*([-*_])[ \\t]*\\1[ \\t]*\\1[ \\t]*(?:\\1[ \\t]*)*$"
        )

        // Links — must NOT match `![alt](url)` (image pass runs first and excludes them).
        static let link = regex("(?<!!)\\[[^\\]\\n]+\\]\\([^)\\n]+\\)")

        // Images `![alt](url)`.
        static let image = regex("!\\[[^\\]\\n]*\\]\\([^)\\n]+\\)")

        // Autolinks: `<https://…>` and bare `https://`/`http://` URLs.
        static let autolink = regex(
            "<(https?://[^>\\s]+)>|(?<![\\(\\[])(https?://[^\\s\\)\\]\"'<>]+)"
        )

        // Tables: lines containing at least one `|`.
        static let tableRow = regex("^.*\\|.*$")
        // Separator rows: only `-`, `:`, `|`, space.
        static let tableSeparatorRow = StaticRegex.compile(
            "^\\|?(?:[ \\t]*:?-+:?[ \\t]*\\|)+[ \\t]*:?-+:?[ \\t]*\\|?$"
        )
        // Individual `|` characters for non-separator row pipe dimming.
        static let tablePipe = StaticRegex.compile("\\|")

        // Fenced code blocks: lines starting with ```.
        static let fenceLine = regex("^```.*$")
        // Opening-fence info string: backticks then optional space then the language identifier.
        static let fenceInfo = StaticRegex.compile("^```+\\s*([A-Za-z0-9_+#.-]*)")
        // A closing fence is exactly ``` with optional trailing whitespace.
        static let closingFence = StaticRegex.compile("^```[ \\t]*$")

        static func regex(_ pattern: String) -> NSRegularExpression {
            StaticRegex.compile(pattern, options: [.anchorsMatchLines])
        }
    }
}

// MARK: - Per-construct styling passes

@MainActor
private extension MarkdownHighlighter {

    static func styleFencedCodeBlocks(
        _ s: NSTextStorage, in str: String, ranges: [NSRange], theme: MarkdownTheme
    ) {
        let ns = str as NSString
        for blockRange in ranges {
            s.addAttribute(.font, value: theme.monoFont, range: blockRange)
            s.addAttribute(.foregroundColor, value: theme.codeColor, range: blockRange)
            // Dim the opening fence line.
            let firstLineRange = ns.lineRange(for: NSRange(location: blockRange.location, length: 0))
            s.addAttribute(.foregroundColor, value: theme.markerColor, range: firstLineRange)
            // Dim the closing fence line ONLY when the block is terminated — i.e. the last line
            // of the range actually contains a closing ``` pattern.  For an unterminated block
            // (opening fence with no matching close) the last line is a content line and must keep
            // `codeColor`; applying `markerColor` there was a bug that dimmed real code text.
            let blockEnd = NSMaxRange(blockRange)
            let lastStart = blockEnd > 0 ? blockEnd - 1 : blockRange.location
            let lastLineRange = ns.lineRange(for: NSRange(location: lastStart, length: 0))
            if lastLineRange.location > firstLineRange.location {
                // Dim only a real closing fence; an unterminated block's last line is content.
                let last = ns.substring(with: lastLineRange)
                let hasClosingFence = Patterns.closingFence.firstMatch(
                    in: last, range: NSRange(location: 0, length: (last as NSString).length)) != nil
                if hasClosingFence {
                    s.addAttribute(.foregroundColor, value: theme.markerColor, range: lastLineRange)
                }
            }
        }
    }

    static func styleHeadings(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        Patterns.heading.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            let level = match.range(at: 1).length
            s.addAttribute(.font, value: theme.headingFont(level: level), range: match.range)
            s.addAttribute(.foregroundColor, value: theme.markerColor, range: match.range(at: 1))
        }
    }

    static func styleInlineCode(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        eachMatch(of: Patterns.inlineCode, in: str, excluding: excluded) { range in
            s.addAttribute(.font, value: theme.monoFont, range: range)
            s.addAttribute(.foregroundColor, value: theme.codeColor, range: range)
            s.addAttribute(.backgroundColor, value: theme.codeBlockBackgroundColor, range: range)
        }
    }

    static func styleStrikethrough(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        Patterns.strikethrough.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            let openMarker = match.range(at: 1)
            let content = match.range(at: 2)
            let closeMarker = match.range(at: 3)
            s.addAttribute(.foregroundColor, value: theme.markerColor, range: openMarker)
            s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: content)
            s.addAttribute(.foregroundColor, value: theme.markerColor, range: closeMarker)
        }
    }

    static func styleLists(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        let ns = str as NSString
        Patterns.listMarker.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            // Skip horizontal rules that match the list pattern (e.g. `- - -`).
            let lineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            let trimmedLine = ns.substring(with: MarkdownListSyntax.trimmedRange(ns, lineRange))
            if isHorizontalRuleLine(trimmedLine) { return }
            let markerRange = match.range(at: 1)
            s.addAttribute(.foregroundColor, value: theme.accentColor, range: markerRange)
            s.addAttribute(.font, value: theme.boldFont, range: markerRange)
            applyTaskCheckbox(s, in: ns, itemSpan: NSRange(location: NSMaxRange(match.range),
                                                            length: NSMaxRange(lineRange) - NSMaxRange(match.range)),
                              theme: theme)
        }
    }

    /// Styles the task-list checkbox and (for checked items) the item text.
    /// `itemSpan` is the range within `ns` starting after the list marker and covering to line end.
    static func applyTaskCheckbox(
        _ s: NSTextStorage, in ns: NSString, itemSpan: NSRange, theme: MarkdownTheme
    ) {
        guard itemSpan.length > 0 else { return }
        let restStr = ns.substring(with: itemSpan)
        let restLen = (restStr as NSString).length
        guard let taskMatch = Patterns.taskCheckbox.firstMatch(
            in: restStr, range: NSRange(location: 0, length: restLen)
        ) else { return }

        let checkboxRange = NSRange(location: itemSpan.location + taskMatch.range.location,
                                    length: taskMatch.range.length)
        s.addAttribute(.foregroundColor, value: theme.accentColor, range: checkboxRange)
        s.addAttribute(.font, value: theme.boldFont, range: checkboxRange)

        // For checked items `[x]`, dim the rest of the line and apply strikethrough.
        let checkboxStr = (restStr as NSString).substring(with: taskMatch.range)
        guard checkboxStr.lowercased().contains("x") else { return }
        let contentStart = itemSpan.location + NSMaxRange(taskMatch.range)
        let lineEnd = NSMaxRange(itemSpan)
        guard contentStart < lineEnd else { return }
        let contentRange = NSRange(location: contentStart, length: lineEnd - contentStart)
        let trimmed = MarkdownListSyntax.trimmedRange(ns, contentRange)
        guard trimmed.length > 0 else { return }
        s.addAttribute(.foregroundColor, value: theme.markerColor, range: trimmed)
        s.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: trimmed)
    }

    static func styleQuotes(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        eachMatch(of: Patterns.quote, in: str, excluding: excluded) { range in
            s.addAttribute(.foregroundColor, value: theme.quoteColor, range: range)
        }
    }

    static func styleHorizontalRules(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        eachMatch(of: Patterns.horizontalRule, in: str, excluding: excluded) { range in
            s.addAttribute(.foregroundColor, value: theme.markerColor, range: range)
        }
    }

    static func styleImages(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        eachMatch(of: Patterns.image, in: str, excluding: excluded) { range in
            s.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    static func styleLinks(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        eachMatch(of: Patterns.link, in: str, excluding: excluded) { range in
            s.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    static func styleAutolinks(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        let ns = str as NSString
        Patterns.autolink.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let range = match?.range, !intersects(range, with: excluded) else { return }
            // Skip if already colored as a link (set by the image or link passes).
            if let color = s.attribute(.foregroundColor, at: range.location, effectiveRange: nil)
                as? NSColor, color == theme.linkColor { return }
            // Skip URLs already inside `[text](url)` or `![alt](url)` — preceded by `(`.
            if range.location > 0, ns.character(at: range.location - 1) == UInt16(UnicodeScalar("(").value) {
                return
            }
            s.addAttribute(.foregroundColor, value: theme.linkColor, range: range)
            s.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range)
        }
    }

    static func styleTables(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        Patterns.tableRow.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let range = match?.range, !intersects(range, with: excluded) else { return }
            let line = (str as NSString).substring(with: range)
            let lineLen = (line as NSString).length
            let isSeparator = Patterns.tableSeparatorRow.firstMatch(
                in: line, range: NSRange(location: 0, length: lineLen)
            ) != nil
            if isSeparator {
                s.addAttribute(.foregroundColor, value: theme.markerColor, range: range)
            } else {
                Patterns.tablePipe.enumerateMatches(
                    in: line, range: NSRange(location: 0, length: lineLen)
                ) { pipeMatch, _, _ in
                    guard let pipeMatch else { return }
                    let pipeRange = NSRange(location: range.location + pipeMatch.range.location,
                                           length: pipeMatch.range.length)
                    s.addAttribute(.foregroundColor, value: theme.markerColor, range: pipeRange)
                }
            }
        }
    }

}
