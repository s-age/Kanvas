import XCTest
@testable import KanvasCore

/// Tests for `MarkdownHighlighter.styleParagraphs` — the paragraph styling pass.
///
/// Each test applies the full highlighter (which runs `styleParagraphs` as its last step) and
/// then reads back `.paragraphStyle` attributes to verify the contract:
/// - List lines receive a `headIndent` ≥ measured prefix width; `firstLineHeadIndent` stays 0.
/// - List lines that are horizontal rules are excluded from the list indent.
/// - Task-list items (`- [x]`) receive the same hanging indent as regular list items.
/// - Nested list lines (extra leading spaces) are indented wider than un-nested lines.
/// - Code-block lines do NOT receive list/heading/quote paragraph tweaks.
/// - Quote lines receive both `firstLineHeadIndent` and `headIndent` = borderWidth + 6.
/// - All lines carry `lineSpacing` from the theme.
/// - Plain (non-list, non-heading, non-quote) lines carry only `lineSpacing`.
///
/// `@MainActor`-isolated because `MarkdownHighlighter` and `MarkdownTheme` are `@MainActor`.
@MainActor
final class MarkdownHighlighterParagraphTests: XCTestCase {

    // MARK: - Helpers

    private let theme = MarkdownTheme.default

    private func applied(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownHighlighter.apply(to: storage, theme: theme)
        return storage
    }

    private func paragraphStyle(_ storage: NSTextStorage, at index: Int) -> NSParagraphStyle? {
        guard index < storage.length else { return nil }
        return storage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle
    }

    // MARK: - Base line spacing on plain lines

    func testPlainLine_hasBaseLineSpacing() {
        let storage = applied("Hello world\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertNotNil(style)
        XCTAssertEqual(style?.lineSpacing, theme.lineSpacing)
    }

    func testPlainLine_headIndentIsZero() {
        let storage = applied("Hello world\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.headIndent ?? 0, 0, accuracy: 0.001)
    }

    // MARK: - List hanging indent

    func testBulletListLine_headIndentIsPositive() {
        // A bullet-list line must have headIndent > 0 (the prefix "- " has measurable width).
        let storage = applied("- item text\n")
        let style = paragraphStyle(storage, at: 0)
        let headIndent = style?.headIndent ?? 0
        XCTAssertGreaterThan(headIndent, 0,
                             "bullet list line should have a positive headIndent for wrapped lines")
    }

    func testBulletListLine_firstLineHeadIndentIsZero() {
        // Source mode: the marker is typed, so the first line starts at column 0.
        let storage = applied("- item text\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.firstLineHeadIndent ?? -1, 0, accuracy: 0.001,
                       "firstLineHeadIndent must be 0 in source mode")
    }

    func testOrderedListLine_headIndentIsPositive() {
        let storage = applied("1. first item\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertGreaterThan(style?.headIndent ?? 0, 0)
    }

    func testTaskListLine_headIndentIsPositive() {
        let storage = applied("- [ ] task item\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertGreaterThan(style?.headIndent ?? 0, 0)
    }

    func testCheckedTaskListLine_headIndentIsPositive() {
        let storage = applied("- [x] done task\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertGreaterThan(style?.headIndent ?? 0, 0)
    }

    func testNestedListLine_headIndentWiderThanUnnested() {
        // A nested item (two leading spaces) has a wider prefix → wider headIndent.
        let text = "- outer\n  - inner\n"
        let storage = applied(text)
        let ns = text as NSString
        let outerStyle = paragraphStyle(storage, at: 0)
        // Find start of the nested line.
        let outerLineRange = ns.lineRange(for: NSRange(location: 0, length: 0))
        let innerStart = NSMaxRange(outerLineRange)
        let innerStyle = paragraphStyle(storage, at: innerStart)
        let outerIndent = outerStyle?.headIndent ?? 0
        let innerIndent = innerStyle?.headIndent ?? 0
        XCTAssertGreaterThan(innerIndent, outerIndent,
                             "nested list line should have wider headIndent than its parent")
    }

    func testListLine_hasBodyLineSpacing() {
        let storage = applied("- item\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.lineSpacing ?? -1, theme.lineSpacing, accuracy: 0.001)
    }

    // MARK: - Horizontal rule excluded from list indent

    func testHorizontalRuleMatchingListPattern_noListIndent() {
        // `- - -` matches the list regex but is a horizontal rule — must not get a list headIndent.
        let storage = applied("- - -\n")
        let style = paragraphStyle(storage, at: 0)
        // The base paragraph style has headIndent = 0; the horizontal rule must not override it.
        XCTAssertEqual(style?.headIndent ?? 0, 0, accuracy: 0.001)
    }

    // MARK: - Code-block lines excluded from list/heading/quote tweaks

    func testCodeBlockLine_noListIndent() {
        // A list-like line inside a fenced code block must not get a hanging indent.
        let text = "```\n- not a list\n```\n"
        let storage = applied(text)
        let ns = text as NSString
        // The "- not a list" line starts at offset 4 (after "```\n").
        let innerStart = 4
        let style = paragraphStyle(storage, at: innerStart)
        XCTAssertEqual(style?.headIndent ?? 0, 0, accuracy: 0.001,
                       "list-like line inside code block must not receive a hanging indent")
    }

    func testCodeBlockLine_noHeadingSpacingBefore() {
        let text = "```\n# Not a heading\n```\n"
        let storage = applied(text)
        let innerStart = 4
        let style = paragraphStyle(storage, at: innerStart)
        XCTAssertEqual(style?.paragraphSpacingBefore ?? 0, 0, accuracy: 0.001,
                       "heading-like line inside code block must not receive paragraphSpacingBefore")
    }

    // MARK: - Quote text inset

    func testQuoteLine_firstLineHeadIndentIsPositive() {
        let storage = applied("> quote text\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertGreaterThan(style?.firstLineHeadIndent ?? 0, 0,
                             "quote line must have positive firstLineHeadIndent to clear the bar")
    }

    func testQuoteLine_headIndentEqualsFirstLineHeadIndent() {
        // Both indents should be the same so wrapped quote lines align with the first line.
        let storage = applied("> quote text\n")
        let style = paragraphStyle(storage, at: 0)
        let fli = style?.firstLineHeadIndent ?? 0
        let hi = style?.headIndent ?? 0
        XCTAssertEqual(fli, hi, accuracy: 0.001,
                       "firstLineHeadIndent and headIndent must match on quote lines")
    }

    func testQuoteLine_insetEqualsBarWidthPlusClearance() {
        // Contract: inset = quoteBorderWidth + MarkdownDecorationPainter.quoteBarClearance.
        let expected = theme.quoteBorderWidth + MarkdownDecorationPainter.quoteBarClearance
        let storage = applied("> quote text\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.firstLineHeadIndent ?? 0, expected, accuracy: 0.001)
    }

    func testQuoteLine_hasBodyLineSpacing() {
        let storage = applied("> quote text\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.lineSpacing ?? -1, theme.lineSpacing, accuracy: 0.001)
    }

    // MARK: - Heading spacing-before

    func testHeadingLine_paragraphSpacingBeforeIsPositive() {
        let storage = applied("# Heading One\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertGreaterThan(style?.paragraphSpacingBefore ?? 0, 0,
                             "heading line must have positive paragraphSpacingBefore")
    }

    func testHeadingLine_hasBodyLineSpacing() {
        let storage = applied("## Heading Two\n")
        let style = paragraphStyle(storage, at: 0)
        XCTAssertEqual(style?.lineSpacing ?? -1, theme.lineSpacing, accuracy: 0.001)
    }
}
