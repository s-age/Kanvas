import AppKit

/// Fenced-code-block resolution and per-language syntax colouring for `MarkdownHighlighter`.
/// Split out of `MarkdownHighlighter.swift` to keep that file under the SwiftLint length limit.
///
/// `fencedCodeBlocks(in:)` extends the original `[NSRange]` block-range resolver with each block's
/// info string and inter-fence content range; `styleCodeBlockSyntax` layers per-token colours
/// (resolved via `CodeHighlighterRegistry` + `GitHubSyntaxPalette`) on top of the mono+codeColor
/// base, and marks diff added/removed lines with `.diffLineKind` for the painter's full-width fill.
@MainActor
extension MarkdownHighlighter {

    /// One fenced code block: its full block range (including both fences + trailing newline), its
    /// lower-cased info string (language identifier from the opening fence; `""` when absent), and
    /// the `contentRange` between the fences (excluding the fence lines) — the region a per-language
    /// highlighter tokenises. Pure value type; the data itself is AppKit-free so it stays testable.
    struct FencedCodeBlock: Equatable {
        let blockRange: NSRange
        let infoString: String
        let contentRange: NSRange
    }

    /// Returns every fenced code block in `str` with its info string and inter-fence content range.
    /// The info string is captured from the opening fence's `^```+\s*([A-Za-z0-9_+#.-]*)` group and
    /// lower-cased. Unterminated blocks extend from their opening fence to the end of text, and
    /// their `contentRange` runs from just after the opening fence line to end of text.
    static func fencedCodeBlocks(in str: String) -> [FencedCodeBlock] {
        let ns = str as NSString
        var blocks: [FencedCodeBlock] = []
        var openFenceStart: Int?
        var openContentStart = 0
        var openInfoString = ""

        let full = NSRange(location: 0, length: ns.length)
        Patterns.fenceLine.enumerateMatches(in: str, range: full) { match, _, _ in
            guard let match else { return }
            // Use the full line range (including the trailing newline) so the fenced block
            // range ends after the newline that follows the closing ```.
            let fullLineRange = ns.lineRange(for: NSRange(location: match.range.location, length: 0))
            let lineContent = ns.substring(with: match.range)
            let contentLen = match.range.length

            if openFenceStart == nil {
                // Opening fence — capture the info string (language identifier) after the backticks.
                openFenceStart = fullLineRange.location
                openContentStart = NSMaxRange(fullLineRange)
                openInfoString = infoString(from: lineContent)
            } else {
                // Closing fence: exactly ``` with optional trailing whitespace.
                let isClose = Patterns.closingFence.firstMatch(
                    in: lineContent,
                    range: NSRange(location: 0, length: contentLen)
                ) != nil
                if isClose {
                    let start = openFenceStart!
                    let blockRange = NSRange(location: start, length: NSMaxRange(fullLineRange) - start)
                    let contentEnd = min(fullLineRange.location, NSMaxRange(blockRange))
                    let contentRange = NSRange(location: openContentStart,
                                               length: max(0, contentEnd - openContentStart))
                    blocks.append(FencedCodeBlock(blockRange: blockRange,
                                                  infoString: openInfoString,
                                                  contentRange: contentRange))
                    openFenceStart = nil
                }
                // Another opening fence mid-block is ignored (still inside the block).
            }
        }
        // Unterminated: block extends to end of text; content runs from after the opening fence.
        if let start = openFenceStart {
            let blockRange = NSRange(location: start, length: ns.length - start)
            let contentRange = NSRange(location: openContentStart,
                                       length: max(0, ns.length - openContentStart))
            blocks.append(FencedCodeBlock(blockRange: blockRange,
                                          infoString: openInfoString,
                                          contentRange: contentRange))
        }
        return blocks
    }

    /// Extracts the lower-cased info string (language identifier) from an opening fence line, or
    /// `""` when none is present.
    static func infoString(from openFenceLine: String) -> String {
        let len = (openFenceLine as NSString).length
        guard let match = Patterns.fenceInfo.firstMatch(
            in: openFenceLine, range: NSRange(location: 0, length: len)
        ), match.numberOfRanges > 1 else { return "" }
        let group = match.range(at: 1)
        guard group.location != NSNotFound, group.length > 0 else { return "" }
        return (openFenceLine as NSString).substring(with: group).lowercased()
    }

    /// Layers per-language syntax colouring on top of the mono+codeColor base for each fenced code
    /// block whose info string resolves to a registered highlighter. Adds `.foregroundColor` per
    /// token and, for diff added/removed tokens, the `.diffLineKind` attribute (the painter draws
    /// the full-width line background from it). Blocks with no / unsupported language are left as-is.
    static func styleCodeBlockSyntax(
        _ s: NSTextStorage, in str: String, blocks: [FencedCodeBlock], theme: MarkdownTheme
    ) {
        let ns = str as NSString
        for block in blocks where !block.infoString.isEmpty {
            guard let highlighter = CodeHighlighterRegistry.highlighter(for: block.infoString),
                  block.contentRange.length > 0,
                  NSMaxRange(block.contentRange) <= ns.length else { continue }
            let content = ns.substring(with: block.contentRange)
            // Highlighters tokenise the substring in its own coordinate space (origin 0); offset
            // each token back to the document coordinate space.
            let localRange = NSRange(location: 0, length: (content as NSString).length)
            applyTokens(highlighter.tokens(in: content, range: localRange),
                        offset: block.contentRange.location, to: s, theme: theme)
        }
    }

    /// Applies a highlighter's tokens to the storage, offsetting each token into document space.
    /// Foreground colours come from the resolved `theme.syntaxColors` (built-in palette + settings
    /// overrides), so a per-board recolour takes effect with no change here.
    private static func applyTokens(
        _ tokens: [CodeToken], offset: Int, to s: NSTextStorage, theme: MarkdownTheme
    ) {
        let length = s.length
        for token in tokens {
            let docRange = NSRange(location: token.range.location + offset, length: token.range.length)
            guard NSMaxRange(docRange) <= length else { continue }
            // `syntaxColors` is total over `CodeTokenKind` (the resolver seeds every kind), so the
            // fallback only guards an impossible miss.
            let color = theme.syntaxColors[token.kind] ?? NSColor.labelColor
            s.addAttribute(.foregroundColor, value: color, range: docRange)
            if GitHubSyntaxPalette.isBold(token.kind), docRange.length > 0,
               let baseFont = s.attribute(.font, at: docRange.location, effectiveRange: nil) as? NSFont {
                // Bold the diff hunk header while preserving the mono font's point size.
                s.addAttribute(.font,
                               value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .bold),
                               range: docRange)
            }
            if let lineKind = diffLineKind(for: token.kind) {
                s.addAttribute(.diffLineKind, value: lineKind, range: docRange)
            }
        }
    }

    /// Maps a diff token kind to the `DiffLineKind` driving the line-background decoration.
    private static func diffLineKind(for kind: CodeTokenKind) -> DiffLineKind? {
        switch kind {
        case .diffAdded: return .added
        case .diffRemoved: return .removed
        default: return nil
        }
    }
}
