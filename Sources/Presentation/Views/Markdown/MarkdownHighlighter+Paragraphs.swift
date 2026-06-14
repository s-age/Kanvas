import AppKit

// MARK: - Paragraph styling pass

/// Paragraph styling pass for `MarkdownHighlighter` — split into its own file so the main
/// highlighter file stays within the SwiftLint `file_length` limit.
///
/// `styleParagraphs` runs after all colour/font passes so the font already applied to each line
/// can be read back for accurate prefix-width measurement on list lines.
@MainActor
extension MarkdownHighlighter {

    /// Applies per-line `NSParagraphStyle` attributes:
    /// - **Quote inset**: `firstLineHeadIndent` and `headIndent` = `quoteBorderWidth + quoteBarClearance`
    ///   so the `>` marker (visible in source mode) clears the decoration bar drawn at `insetX`.
    ///   `quoteBarClearance` is the single source of truth on `MarkdownDecorationPainter`.
    ///   The bar is always rendered at view-coordinate `x = insetX` regardless of paragraph indent,
    ///   so the indent only pushes text right — bar and text never collide.
    /// - **List hanging indent**: `headIndent` = measured prefix width + `listIndentWidth`.
    ///   Prefix width is measured with the font already set on the line (exact for proportional
    ///   body fonts). `firstLineHeadIndent` stays 0 — source mode, the marker is the first char.
    /// - **List item spacing**: `paragraphSpacing` from `theme.listItemSpacing`.
    /// - **Heading spacing-before**: `paragraphSpacingBefore = 0.5 × headingFontSize`.
    /// - **All lines**: `lineSpacing` from `theme.lineSpacing` (already on every line via the base
    ///   paragraph style set in `apply`; re-stated on each per-construct style for consistency).
    ///
    /// Code-block lines skip the list/heading/quote tweaks (they are in `excluded`).
    static func styleParagraphs(
        _ s: NSTextStorage, in str: String, excluding excluded: [NSRange], theme: MarkdownTheme
    ) {
        let ns = str as NSString

        // Quote inset: borderWidth + clearance keeps the `>` marker and text from overlapping the
        // decoration bar. `quoteBarClearance` is the single source of truth shared with the painter.
        let quoteInset = theme.quoteBorderWidth + MarkdownDecorationPainter.quoteBarClearance
        Patterns.quote.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            let lineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            let style = NSMutableParagraphStyle()
            style.lineSpacing = theme.lineSpacing
            style.firstLineHeadIndent = quoteInset
            style.headIndent = quoteInset
            s.addAttribute(.paragraphStyle, value: style, range: lineRange)
        }

        // List hanging indent and item spacing.
        Patterns.listMarker.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            let lineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            // Skip horizontal-rule lines that happen to match the list pattern (e.g. `- - -`).
            let trimmedRange = MarkdownListSyntax.trimmedRange(ns, lineRange)
            let trimmed = ns.substring(with: trimmedRange)
            guard !isHorizontalRuleLine(trimmed) else { return }
            // Measure the full marker prefix (leading whitespace + bullet/number + trailing space)
            // with the font already on that line — critical for proportional body fonts.
            let prefixStr = ns.substring(with: match.range)
            let lineFont = s.attribute(.font, at: match.range.location,
                                       effectiveRange: nil) as? NSFont ?? theme.baseFont
            let prefixWidth = (prefixStr as NSString).size(withAttributes: [.font: lineFont]).width
            let hangIndent = prefixWidth + theme.listIndentExtra
            let style = NSMutableParagraphStyle()
            style.lineSpacing = theme.lineSpacing
            style.headIndent = hangIndent
            // firstLineHeadIndent stays 0: source mode — the typed marker provides the visual indent.
            style.paragraphSpacing = theme.listItemSpacing
            s.addAttribute(.paragraphStyle, value: style, range: lineRange)
        }

        // Heading spacing-before: 0.5 × heading font size. Applied last so headings never
        // accidentally inherit a list paragraph style from the pass above.
        Patterns.heading.enumerateMatches(in: str, range: fullRange(str)) { match, _, _ in
            guard let match, !intersects(match.range, with: excluded) else { return }
            let level = match.range(at: 1).length
            let headingFont = theme.headingFont(level: level)
            let style = NSMutableParagraphStyle()
            style.lineSpacing = theme.lineSpacing
            style.paragraphSpacingBefore = headingFont.pointSize * 0.5
            s.addAttribute(.paragraphStyle, value: style, range: match.range)
        }
    }
}
