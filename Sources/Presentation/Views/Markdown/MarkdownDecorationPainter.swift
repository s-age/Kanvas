import AppKit

// MARK: - Decoration range model

/// A classified range for block-level decoration drawing: either a fenced code block (full-width
/// background) or a contiguous run of consecutive blockquote lines (left border bar).
enum DecorationKind {
    case codeBlock
    case quoteRun
}

/// A contiguous text range paired with its decoration kind, computed from the raw string by
/// `MarkdownDecorationPainter.decorationRanges(in:)`. Deliberately free of AppKit so the logic
/// can be unit-tested without a display context.
struct DecorationRange: Equatable {
    let kind: DecorationKind
    let range: NSRange
}

// MARK: - Range classification

/// Computes decoration ranges from a Markdown string, then draws them behind the text in an
/// `NSTextView` backed by TextKit 1.
///
/// **Classification** (`decorationRanges(in:)`) is pure and testable: it reuses
/// `MarkdownHighlighter.fencedCodeBlockRanges(in:)` for fenced blocks and the same
/// `Patterns.quote` regex for blockquote lines, merging adjacent quote lines into contiguous runs.
///
/// **Drawing** (`drawDecorations(in:theme:)`) maps each `DecorationRange` to its glyph-fragment
/// rect via `NSLayoutManager.enumerateLineFragments(forGlyphRange:using:)`, insets to the text
/// container width, and fills a rounded rect (code blocks) or a narrow vertical bar (quote runs).
///
/// `@MainActor`-isolated to match `MarkdownTheme`'s `NSFont`/`NSColor` fields and the
/// `NSLayoutManager` it queries; all callers are main-actor `NSTextView` hooks.
@MainActor
enum MarkdownDecorationPainter {

    /// Gap in points between the right edge of the quote border bar and the start of the quote
    /// text.  `MarkdownHighlighter+Paragraphs` uses `quoteBorderWidth + quoteBarClearance` for
    /// the paragraph `firstLineHeadIndent` / `headIndent` so the source `>` marker and text
    /// always clear the bar.  Both sides must stay in sync — see
    /// `MarkdownHighlighterParagraphTests.testQuoteLine_insetEqualsBarWidthPlusClearance`
    /// which asserts the inset contract.
    static let quoteBarClearance: CGFloat = 6

    // MARK: - Pure range classification (unit-testable)

    /// Returns the decoration ranges for `str`, sorted by location. Fenced code block ranges come
    /// from `MarkdownHighlighter.fencedCodeBlockRanges(in:)`; blockquote ranges are built by
    /// merging adjacent lines that match `MarkdownHighlighter.Patterns.quote`.
    static func decorationRanges(in str: String) -> [DecorationRange] {
        var result: [DecorationRange] = []

        // Fenced code blocks — reuse the highlighter's resolver.
        for range in MarkdownHighlighter.fencedCodeBlockRanges(in: str) {
            result.append(DecorationRange(kind: .codeBlock, range: range))
        }

        // Blockquote runs — collect individual quote lines, then merge consecutive ones.
        // Lines that overlap a fenced code block are excluded so `> foo` inside a fence does not
        // produce a spurious quote-run decoration over the code background.
        let codeBlockRanges = result.map { $0.range }   // already populated above
        let ns = str as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var quoteLineRanges: [NSRange] = []
        MarkdownHighlighter.Patterns.quote.enumerateMatches(in: str, range: fullRange) { match, _, _ in
            guard let match else { return }
            // Expand to the full line (including trailing newline) so adjacent-line merging works.
            let lineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            // Skip this quote line if it falls inside a fenced code block.
            guard !MarkdownHighlighter.intersects(lineRange, with: codeBlockRanges) else { return }
            quoteLineRanges.append(lineRange)
        }

        // Merge consecutive (touching) line ranges into contiguous quote runs.
        for lineRange in quoteLineRanges {
            if let last = result.last, last.kind == .quoteRun,
               NSMaxRange(last.range) == lineRange.location {
                // Extend the last quote run.
                let merged = NSRange(location: last.range.location,
                                     length: last.range.length + lineRange.length)
                result[result.count - 1] = DecorationRange(kind: .quoteRun, range: merged)
            } else {
                result.append(DecorationRange(kind: .quoteRun, range: lineRange))
            }
        }

        return result.sorted { $0.range.location < $1.range.location }
    }

    // MARK: - Drawing

    /// Draws block decorations behind the text using the TextKit 1 layout manager. Must be called
    /// from within an `NSView.drawBackground(in:)` override while the graphics context is valid.
    ///
    /// - Parameters:
    ///   - textView: The editor's `NSTextView` whose layout manager is used for glyph lookups.
    ///   - decorations: Pre-computed decoration ranges (from `decorationRanges(in:)`); passing
    ///     them in avoids re-running two full-document regex sweeps on every draw pass.
    ///   - dirtyRect: The rect passed to `drawBackground` — used to skip decorations whose
    ///     fragment rects lie entirely outside the dirty region.
    ///   - theme: The resolved theme supplying decoration colors and border width.
    static func drawDecorations(
        in textView: NSTextView,
        decorations: [DecorationRange],
        dirtyRect: NSRect,
        theme: MarkdownTheme
    ) {
        guard let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        let str = textView.string
        let ns = str as NSString
        let inset = textView.textContainerInset
        let containerWidth = textContainer.containerSize.width

        for decoration in decorations where !str.isEmpty {
            // Convert character range → glyph range.
            let charRange = decoration.range
            guard charRange.location <= ns.length else { continue }
            let safeCharRange = NSRange(location: charRange.location,
                                        length: min(charRange.length, ns.length - charRange.location))
            guard safeCharRange.length > 0 else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: safeCharRange,
                                                       actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            // Collect the union of all line-fragment rects for this glyph range.
            var unionRect: CGRect = .null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                if unionRect.isNull {
                    unionRect = usedRect
                } else {
                    unionRect = unionRect.union(usedRect)
                }
            }
            guard !unionRect.isNull else { continue }

            // Derive the view-coordinate y origin and height shared by both decoration kinds.
            let insetX = inset.width
            let drawY = unionRect.origin.y + inset.height
            let drawH = unionRect.height

            // Cull against the DRAWN rect for this decoration kind rather than the text-union rect.
            // The code-block fill spans the full container width (potentially wider than the text
            // rect), and the quote bar starts at x = insetX (potentially left of the line-fragment
            // rect due to line-fragment padding). Using the text-union rect would skip either kind
            // when a narrow dirty strip overlaps only the drawn area but not the text rect.
            switch decoration.kind {
            case .codeBlock:
                let drawnRect = CGRect(x: insetX, y: drawY, width: containerWidth, height: drawH)
                guard drawnRect.intersects(dirtyRect) else { continue }
                drawCodeBlockBackground(drawnRect,
                                        containerWidth: containerWidth,
                                        insetX: insetX,
                                        color: theme.codeBlockBackgroundColor)
            case .quoteRun:
                let barRect = CGRect(x: insetX, y: drawY,
                                     width: theme.quoteBorderWidth, height: drawH)
                guard barRect.intersects(dirtyRect) else { continue }
                drawQuoteBorderBar(barRect,
                                   insetX: insetX,
                                   color: theme.quoteBorderColor,
                                   width: theme.quoteBorderWidth)
            }
        }

        // Diff line backgrounds are resolved from the `.diffLineKind` attributes the highlighter
        // applied (not from `decorations`, which is a pure string-derived classification). Drawn
        // LAST — after the opaque code-block fill — so the green/red full-width diff line
        // backgrounds layer on top of the code-block background instead of being hidden by it
        // (the code-block fill from `NSColor(hex:)` is always alpha:1 / opaque).
        drawDiffLineBackgrounds(in: textView, dirtyRect: dirtyRect, theme: theme)
    }

    // MARK: - Diff line backgrounds (full-width, attribute-driven)

    /// One diff line's full-width background: the character range carrying a `.diffLineKind`
    /// attribute plus the resolved kind. Unit-testable independent of layout.
    struct DiffLineBackground: Equatable {
        let range: NSRange
        let kind: DiffLineKind
    }

    /// Returns the `.diffLineKind`-attributed ranges in `storage`, each paired with its kind. Pure
    /// (no layout) so the resolution from highlighter attributes to background ranges is testable.
    static func diffLineBackgroundRanges(in storage: NSAttributedString) -> [DiffLineBackground] {
        var result: [DiffLineBackground] = []
        let full = NSRange(location: 0, length: storage.length)
        storage.enumerateAttribute(.diffLineKind, in: full) { value, range, _ in
            guard let kind = value as? DiffLineKind, range.length > 0 else { return }
            result.append(DiffLineBackground(range: range, kind: kind))
        }
        return result
    }

    /// Draws the full-width line backgrounds for every `.diffLineKind`-attributed run.
    private static func drawDiffLineBackgrounds(
        in textView: NSTextView, dirtyRect: NSRect, theme: MarkdownTheme
    ) {
        guard let storage = textView.textStorage,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }
        let ns = textView.string as NSString
        let inset = textView.textContainerInset
        let containerWidth = textContainer.containerSize.width
        for diff in diffLineBackgroundRanges(in: storage) {
            guard let color = theme.syntaxLineBackgrounds[lineKindToTokenKind(diff.kind)],
                  diff.range.location <= ns.length else { continue }
            let safe = NSRange(location: diff.range.location,
                               length: min(diff.range.length, ns.length - diff.range.location))
            guard safe.length > 0 else { continue }
            let glyphRange = layoutManager.glyphRange(forCharacterRange: safe, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }

            var unionRect: CGRect = .null
            layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, _, _, _ in
                unionRect = unionRect.isNull ? usedRect : unionRect.union(usedRect)
            }
            guard !unionRect.isNull else { continue }
            let drawnRect = CGRect(x: inset.width, y: unionRect.origin.y + inset.height,
                                   width: containerWidth, height: unionRect.height)
            guard drawnRect.intersects(dirtyRect) else { continue }
            color.setFill()
            drawnRect.fill()
        }
    }

    private static func lineKindToTokenKind(_ kind: DiffLineKind) -> CodeTokenKind {
        switch kind {
        case .added: return .diffAdded
        case .removed: return .diffRemoved
        }
    }

    // MARK: - Per-kind drawing helpers

    private static func drawCodeBlockBackground(
        _ lineUnionRect: CGRect,
        containerWidth: CGFloat,
        insetX: CGFloat,
        color: NSColor
    ) {
        // Span the full content width (text container width), aligned to the left inset edge.
        let rect = CGRect(
            x: insetX,
            y: lineUnionRect.origin.y,
            width: containerWidth,
            height: lineUnionRect.height
        )
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
    }

    private static func drawQuoteBorderBar(
        _ lineUnionRect: CGRect,
        insetX: CGFloat,
        color: NSColor,
        width: CGFloat
    ) {
        // Draw at the left edge of the text container inset margin.
        let rect = CGRect(
            x: insetX,
            y: lineUnionRect.origin.y,
            width: width,
            height: lineUnionRect.height
        )
        color.setFill()
        NSBezierPath(rect: rect).fill()
    }
}
