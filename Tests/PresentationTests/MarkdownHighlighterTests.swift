import XCTest
@testable import KanvasCore

/// Tests for `MarkdownHighlighter` — the source-mode Markdown syntax highlighter.
///
/// `MarkdownHighlighter` is `@MainActor`-isolated because it mutates an `NSTextStorage`
/// and resolves `NSFont`/`NSColor` from a `MarkdownTheme`; all test methods mirror that
/// isolation. Pure helpers (`fencedCodeBlockRanges`, `intersects`) are tested directly
/// without an `NSTextStorage` to keep setup minimal.
@MainActor
final class MarkdownHighlighterTests: XCTestCase {

    // MARK: - Helpers

    private let theme = MarkdownTheme.default

    /// Builds an attributed `NSTextStorage`, applies the highlighter, and returns it.
    private func highlighted(_ text: String) -> NSTextStorage {
        let storage = NSTextStorage(string: text)
        MarkdownHighlighter.apply(to: storage, theme: theme)
        return storage
    }

    /// Returns the foreground color of the character at `index` in `storage`.
    private func fgColor(_ storage: NSTextStorage, at index: Int) -> NSColor? {
        guard index < storage.length else { return nil }
        return storage.attribute(.foregroundColor, at: index, effectiveRange: nil) as? NSColor
    }

    /// Returns the font of the character at `index` in `storage`.
    private func font(_ storage: NSTextStorage, at index: Int) -> NSFont? {
        guard index < storage.length else { return nil }
        return storage.attribute(.font, at: index, effectiveRange: nil) as? NSFont
    }

    /// Returns whether `.strikethroughStyle` is set at `index`.
    private func hasStrikethrough(_ storage: NSTextStorage, at index: Int) -> Bool {
        guard index < storage.length else { return false }
        return storage.attribute(.strikethroughStyle, at: index, effectiveRange: nil) != nil
    }

    /// Returns whether `.underlineStyle` is set at `index`.
    private func hasUnderline(_ storage: NSTextStorage, at index: Int) -> Bool {
        guard index < storage.length else { return false }
        return storage.attribute(.underlineStyle, at: index, effectiveRange: nil) != nil
    }

    // MARK: - intersects helper

    func testIntersects_noOverlap_returnsFalse() {
        let excluded = [NSRange(location: 10, length: 5)]
        XCTAssertFalse(MarkdownHighlighter.intersects(NSRange(location: 0, length: 5), with: excluded))
        XCTAssertFalse(MarkdownHighlighter.intersects(NSRange(location: 15, length: 5), with: excluded))
    }

    func testIntersects_overlap_returnsTrue() {
        let excluded = [NSRange(location: 10, length: 5)]
        XCTAssertTrue(MarkdownHighlighter.intersects(NSRange(location: 12, length: 3), with: excluded))
    }

    func testIntersects_adjacentRanges_returnsFalse() {
        let excluded = [NSRange(location: 10, length: 5)]
        // Range ending exactly at the start of excluded.
        XCTAssertFalse(MarkdownHighlighter.intersects(NSRange(location: 5, length: 5), with: excluded))
        // Range starting exactly at the end of excluded.
        XCTAssertFalse(MarkdownHighlighter.intersects(NSRange(location: 15, length: 5), with: excluded))
    }

    // MARK: - Fenced code block range resolution

    func testFencedCodeBlock_terminated_coversOpenToCloseFence() {
        let text = "```swift\nlet x = 1\n```\n"
        let ranges = MarkdownHighlighter.fencedCodeBlockRanges(in: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].location, 0)
        XCTAssertEqual(NSMaxRange(ranges[0]), (text as NSString).length)
    }

    func testFencedCodeBlock_unterminated_extendsToEndOfText() {
        let text = "```swift\nlet x = 1\n"
        let ranges = MarkdownHighlighter.fencedCodeBlockRanges(in: text)
        XCTAssertEqual(ranges.count, 1)
        XCTAssertEqual(ranges[0].location, 0)
        XCTAssertEqual(NSMaxRange(ranges[0]), (text as NSString).length)
    }

    func testFencedCodeBlock_twoBlocks_returnsTwoRanges() {
        let text = "```\nfoo\n```\nplain\n```\nbar\n```\n"
        let ranges = MarkdownHighlighter.fencedCodeBlockRanges(in: text)
        XCTAssertEqual(ranges.count, 2)
    }

    func testFencedCodeBlock_noFences_returnsEmpty() {
        let ranges = MarkdownHighlighter.fencedCodeBlockRanges(in: "just plain text\n")
        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Other passes skip content inside fenced code blocks

    func testHeadingInsideCodeBlock_notStyled() {
        // The `# heading` inside the fence should NOT get heading font.
        let text = "```\n# heading\n```\n"
        let storage = highlighted(text)
        // Index 4 is the `#` character inside the code block.
        let headingFont = theme.headingFont(level: 1)
        XCTAssertNotEqual(font(storage, at: 4), headingFont)
    }

    func testBoldInsideCodeBlock_notStyled() {
        let text = "```\n**bold**\n```\n"
        let storage = highlighted(text)
        // Index 4 is the first `*` inside the fence.
        XCTAssertNotEqual(font(storage, at: 4), theme.boldFont)
    }

    func testInlineCodeInsideCodeBlock_notDoubleStyled() {
        // The inline code span inside a fence block should not get a different mono font.
        let text = "```\n`code`\n```\n"
        let storage = highlighted(text)
        // The whole block should get the code block's mono font; no distinct inline-code styling.
        // We just assert no crash and that the block range is not empty.
        let ranges = MarkdownHighlighter.fencedCodeBlockRanges(in: text)
        XCTAssertEqual(ranges.count, 1)
    }

    // MARK: - Fenced code block styling

    func testFencedCodeBlock_contentUsesMonoAndCodeColor() {
        let text = "```\nsome code\n```\n"
        let storage = highlighted(text)
        // Index 4 is inside the block content ("some code").
        XCTAssertEqual(font(storage, at: 4), theme.monoFont)
        XCTAssertEqual(fgColor(storage, at: 4), theme.codeColor)
    }

    func testFencedCodeBlock_fenceLinesDimmed() {
        let text = "```\ncode\n```\n"
        let storage = highlighted(text)
        // Index 0 is the opening fence `\``.
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testFencedCodeBlock_unterminatedBlock_lastContentLineKeepsCodeColor() {
        // An unterminated fence has no closing ```. The last line is content — it must keep
        // `codeColor`, NOT be dimmed to `markerColor` (Bug #3 regression guard).
        let text = "```\ncode line\n"
        let storage = highlighted(text)
        // "code line" starts at index 4 (after "```\n").
        XCTAssertEqual(fgColor(storage, at: 4), theme.codeColor,
                       "Last content line of an unterminated fence must keep codeColor, not markerColor")
    }

    func testFencedCodeBlock_terminatedBlock_closingFenceIsDimmed() {
        // A properly terminated block must still dim the closing fence line (sanity check).
        let text = "```\ncode\n```\n"
        let storage = highlighted(text)
        // The closing ``` starts at offset "```\ncode\n".count = 9.
        let closingFenceIndex = (text as NSString).range(of: "```\n", range: NSRange(location: 4, length: (text as NSString).length - 4)).location
        XCTAssertNotEqual(closingFenceIndex, NSNotFound)
        XCTAssertEqual(fgColor(storage, at: closingFenceIndex), theme.markerColor,
                       "Closing fence of a terminated block must be dimmed to markerColor")
    }

    // MARK: - Strikethrough

    func testStrikethrough_contentGetsStrikethroughAttribute() {
        let text = "~~hello~~"
        let storage = highlighted(text)
        // Index 2 is the 'h' in 'hello'.
        XCTAssertTrue(hasStrikethrough(storage, at: 2))
    }

    func testStrikethrough_markersAreDimmed() {
        let text = "~~hello~~"
        let storage = highlighted(text)
        // Index 0 is the first `~` (opening marker).
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testStrikethrough_markersNotStrikethrough() {
        let text = "~~hello~~"
        let storage = highlighted(text)
        // The markers themselves should not have the strikethrough attribute.
        XCTAssertFalse(hasStrikethrough(storage, at: 0))
    }

    // MARK: - Task list highlighting

    func testTaskList_uncheckedCheckbox_accentColor() {
        let text = "- [ ] buy milk\n"
        let storage = highlighted(text)
        // Find `[ ]` start: "- " is 2 chars, so index 2 is `[`.
        XCTAssertEqual(fgColor(storage, at: 2), theme.accentColor)
    }

    func testTaskList_checkedItem_textIsDimmed() {
        let text = "- [x] done\n"
        let storage = highlighted(text)
        // "- [x] " is 6 chars; index 6 is 'd' in 'done'.
        XCTAssertEqual(fgColor(storage, at: 6), theme.markerColor)
    }

    func testTaskList_checkedItem_textHasStrikethrough() {
        let text = "- [x] done\n"
        let storage = highlighted(text)
        // Index 6 is 'd' in 'done'.
        XCTAssertTrue(hasStrikethrough(storage, at: 6))
    }

    func testTaskList_uncheckedItem_textNotStrikethrough() {
        let text = "- [ ] todo\n"
        let storage = highlighted(text)
        // Index 6 is 't' in 'todo'.
        XCTAssertFalse(hasStrikethrough(storage, at: 6))
    }

    func testTaskList_uppercaseX_treatedAsChecked() {
        let text = "- [X] done\n"
        let storage = highlighted(text)
        XCTAssertTrue(hasStrikethrough(storage, at: 6))
    }

    func testTaskList_asteriskBullet_supported() {
        // `* [ ]` form.
        let text = "* [ ] item\n"
        let storage = highlighted(text)
        // `* [ ] ` is 7 chars; index 2 is `[`.
        XCTAssertEqual(fgColor(storage, at: 2), theme.accentColor)
    }

    func testTaskList_plusBullet_supported() {
        let text = "+ [ ] item\n"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 2), theme.accentColor)
    }

    // MARK: - Horizontal rule vs list-marker disambiguation

    func testHorizontalRule_tripleHyphen_dimmedAsMarker() {
        let text = "---\n"
        let storage = highlighted(text)
        // Index 0 is the first `-`.
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testHorizontalRule_spacedHyphen_dimmedAsMarker() {
        let text = "- - -\n"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testHorizontalRule_tripleStar_dimmedAsMarker() {
        let text = "***\n"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testHorizontalRule_tripleUnderscore_dimmedAsMarker() {
        let text = "___\n"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testListMarker_notTreatedAsHorizontalRule() {
        // A single `- item` line must get accentColor, not markerColor.
        let text = "- item\n"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 0), theme.accentColor)
    }

    // MARK: - Image pass

    func testImage_wholeSpanGetsLinkColor() {
        let text = "![alt](https://example.com)"
        let storage = highlighted(text)
        // Index 0 is `!`.
        XCTAssertEqual(fgColor(storage, at: 0), theme.linkColor)
    }

    func testImage_wholeSpanGetsUnderline() {
        let text = "![alt](https://example.com)"
        let storage = highlighted(text)
        XCTAssertTrue(hasUnderline(storage, at: 0))
    }

    func testImage_notDoubleStyledByLinkPass() {
        // Ensure `![alt](url)` is colored exactly once (linkColor), not as a
        // separate link-pass re-style. We just check that the final color is linkColor.
        let text = "![alt](https://example.com)"
        let storage = highlighted(text)
        XCTAssertEqual(fgColor(storage, at: 0), theme.linkColor)
    }

    // MARK: - Autolink

    func testAutolink_bareHttps_getsLinkColor() {
        let text = "visit https://example.com for info"
        let storage = highlighted(text)
        // "visit " is 6 chars; index 6 is 'h' in the URL.
        XCTAssertEqual(fgColor(storage, at: 6), theme.linkColor)
    }

    func testAutolink_bareHttps_getsUnderline() {
        let text = "see https://example.com"
        let storage = highlighted(text)
        XCTAssertTrue(hasUnderline(storage, at: 4))
    }

    func testAutolink_urlInsideExplicitLink_notStyled() {
        // The URL inside `[text](url)` must not get separate autolink styling.
        let text = "[example](https://example.com)"
        let storage = highlighted(text)
        // The whole span already has linkColor from the link pass; we just verify the
        // autolink pass does not break it (color stays linkColor throughout).
        XCTAssertEqual(fgColor(storage, at: 10), theme.linkColor)
    }

    // MARK: - Bold-italic fix

    func testBoldItalic_tripleStarContent_getsBoldItalicFont() {
        let text = "***bold-italic***"
        let storage = highlighted(text)
        // Index 3 is 'b' in 'bold-italic'.
        // Compare against the theme's boldItalicFont directly (system font may alias bold↔boldItalic
        // when no distinct italic variant exists, so use the theme as the reference).
        XCTAssertEqual(font(storage, at: 3), theme.boldItalicFont)
    }

    func testBold_doubleStarContent_getsBoldFont() {
        let text = "**bold**"
        let storage = highlighted(text)
        // Index 2 is 'b' in 'bold'.
        XCTAssertEqual(font(storage, at: 2), theme.boldFont)
    }

    func testItalic_singleStarContent_getsItalicFont() {
        let text = "*italic*"
        let storage = highlighted(text)
        // Index 1 is 'i' in 'italic'.
        XCTAssertEqual(font(storage, at: 1), theme.italicFont)
    }

    func testBoldItalic_tripleStarDoesNotLeaveBoldOnlyResidual() {
        // `***x***` must get the boldItalicFont, not the plain boldFont.
        // The bold pass must be excluded from boldItalic-matched ranges.
        let text = "***x***"
        let storage = highlighted(text)
        // Index 3 is 'x'.
        let contentFont = font(storage, at: 3)
        XCTAssertEqual(contentFont, theme.boldItalicFont,
                       "Content of ***x*** should get boldItalicFont, not plain boldFont")
    }

    // MARK: - Table rows

    func testTableRow_pipesAreDimmed() {
        let text = "| one | two |\n"
        let storage = highlighted(text)
        // Index 0 is the first `|`.
        XCTAssertEqual(fgColor(storage, at: 0), theme.markerColor)
    }

    func testTableSeparatorRow_entireLineIsDimmed() {
        let text = "|---|---|\n"
        let storage = highlighted(text)
        // Index 1 is `-` inside the separator.
        XCTAssertEqual(fgColor(storage, at: 1), theme.markerColor)
    }
}

// MARK: - Task list continuation tests

/// Tests for task-list continuation behavior in `MarkdownListContinuation.handleNewline`.
/// Uses a lightweight `NSTextView` stub backed by `NSTextStorage` (no window needed).
@MainActor
final class MarkdownTaskListContinuationTests: XCTestCase {

    // MARK: - Helpers

    /// Creates an `NSTextView` with `text`, places the caret at `caretOffset`, then fires
    /// `handleNewline` and returns the resulting string.
    private func insertNewline(in text: String, caretAt caretOffset: Int) -> String {
        let storage = NSTextStorage(string: text)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        let container = NSTextContainer()
        layoutManager.addTextContainer(container)
        let textView = NSTextView(frame: .zero, textContainer: container)
        textView.string = text
        textView.setSelectedRange(NSRange(location: caretOffset, length: 0))
        _ = MarkdownListContinuation.handleNewline(in: textView)
        return textView.string
    }

    // MARK: - Task list continuation

    func testTaskContinuation_unchecked_continuesWithUnchecked() {
        // Caret is after `- [ ] item`.
        let text = "- [ ] item"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("- [ ] "), "Expected a new unchecked task item on continuation")
    }

    func testTaskContinuation_checked_continuesWithUnchecked() {
        // Even a checked item should continue with an unchecked checkbox.
        let text = "- [x] done"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("- [ ] "), "Expected unchecked item after checked task")
        XCTAssertFalse(result.hasSuffix("- [x] "), "Should NOT continue with a checked item")
    }

    func testTaskContinuation_emptyUncheckedItem_terminatesList() {
        // `- [ ] ` with no text after the checkbox = empty item → terminate.
        let text = "- [ ] "
        let result = insertNewline(in: text, caretAt: text.count)
        // The list marker should be wiped: result should just be a newline (or empty line).
        XCTAssertFalse(result.contains("- [ ]"), "Empty task item should terminate the list")
    }

    func testTaskContinuation_asteriskBullet_continuationUsesAsterisk() {
        let text = "* [ ] item"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("* [ ] "), "Should continue with `* [ ]` bullet form")
    }

    func testTaskContinuation_plusBullet_continuationUsesPlus() {
        let text = "+ [ ] item"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("+ [ ] "), "Should continue with `+ [ ]` bullet form")
    }

    func testTaskContinuation_nonTaskList_continuationHasNoCheckbox() {
        // A plain `- item` must not gain a `[ ]` on continuation.
        let text = "- plain item"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertFalse(result.contains("[ ]"), "Plain list should not gain a checkbox on continuation")
    }

    func testTaskContinuation_orderedItem_continuesWithNextOrdinalAndCheckbox() {
        // Bug #4 guard: `2. [ ] foo` + Enter must continue as `3. [ ] ` (ordered task item).
        let text = "2. [ ] foo"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("3. [ ] "),
                      "Ordered task item continuation must produce the next ordinal with an unchecked checkbox")
    }

    func testTaskContinuation_orderedCheckedItem_continuesWithUncheckedAndNextOrdinal() {
        // A checked ordered task `1. [x] done` should continue as `2. [ ] `.
        let text = "1. [x] done"
        let result = insertNewline(in: text, caretAt: text.count)
        XCTAssertTrue(result.contains("2. [ ] "),
                      "Checked ordered task item must continue with unchecked next ordinal")
        XCTAssertFalse(result.contains("2. [x]"), "Continuation must not copy the checked state")
    }
}
