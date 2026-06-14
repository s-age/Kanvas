import XCTest
@testable import KanvasCore

/// Tests for `MarkdownDecorationPainter.decorationRanges(in:)` — the pure range-classification
/// step that maps a Markdown string to `[DecorationRange]`. Drawing itself is not unit-tested
/// (it requires a live `NSLayoutManager` context), but the classification is fully testable.
///
/// Verified contracts:
/// - Fenced code blocks are classified as `.codeBlock` with their Phase-1 ranges.
/// - Each contiguous group of consecutive blockquote lines is classified as one `.quoteRun`.
/// - Two non-adjacent quote lines produce two separate `.quoteRun` entries.
/// - An unterminated fence is still classified as `.codeBlock` (extends to end of text).
/// - Mixed content (code + quotes) yields both kinds in location order.
///
/// `@MainActor`-isolated because `MarkdownDecorationPainter` is `@MainActor`.
@MainActor
final class MarkdownDecorationPainterTests: XCTestCase {

    // MARK: - Fenced code blocks

    func testDecorationRanges_terminatedFencedBlock_classifiedAsCodeBlock() {
        let text = "```swift\nlet x = 1\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let blocks = ranges.filter { $0.kind == .codeBlock }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].range.location, 0)
        XCTAssertEqual(NSMaxRange(blocks[0].range), (text as NSString).length)
    }

    func testDecorationRanges_unterminatedFence_classifiedAsCodeBlock() {
        let text = "```swift\nlet x = 1\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let blocks = ranges.filter { $0.kind == .codeBlock }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(NSMaxRange(blocks[0].range), (text as NSString).length)
    }

    func testDecorationRanges_twoFencedBlocks_producesTwoCodeBlockRanges() {
        let text = "```\nfoo\n```\nplain\n```\nbar\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        XCTAssertEqual(ranges.filter { $0.kind == .codeBlock }.count, 2)
    }

    func testDecorationRanges_noFences_producesNoCodeBlocks() {
        let text = "just plain text\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        XCTAssertTrue(ranges.filter { $0.kind == .codeBlock }.isEmpty)
    }

    // MARK: - Blockquote runs

    func testDecorationRanges_singleQuoteLine_classifiedAsQuoteRun() {
        let text = "> hello\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let runs = ranges.filter { $0.kind == .quoteRun }
        XCTAssertEqual(runs.count, 1)
    }

    func testDecorationRanges_twoAdjacentQuoteLines_mergedIntoOneRun() {
        let text = "> line 1\n> line 2\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let runs = ranges.filter { $0.kind == .quoteRun }
        XCTAssertEqual(runs.count, 1, "Adjacent quote lines should be merged into one run")
        // The merged run should span the full text.
        XCTAssertEqual(runs[0].range.location, 0)
        XCTAssertEqual(NSMaxRange(runs[0].range), (text as NSString).length)
    }

    func testDecorationRanges_twoNonAdjacentQuoteLines_produceTwoRuns() {
        let text = "> first\nplain line\n> second\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let runs = ranges.filter { $0.kind == .quoteRun }
        XCTAssertEqual(runs.count, 2, "Non-adjacent quote lines should produce two separate runs")
    }

    func testDecorationRanges_threeConsecutiveQuoteLines_mergedIntoOneRun() {
        let text = "> a\n> b\n> c\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let runs = ranges.filter { $0.kind == .quoteRun }
        XCTAssertEqual(runs.count, 1)
        XCTAssertEqual(NSMaxRange(runs[0].range), (text as NSString).length)
    }

    func testDecorationRanges_noQuotes_producesNoQuoteRuns() {
        let text = "plain\n**bold**\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        XCTAssertTrue(ranges.filter { $0.kind == .quoteRun }.isEmpty)
    }

    // MARK: - Mixed content

    func testDecorationRanges_codeBlockAndQuote_produceBothKinds() {
        let text = "> quoted\n```\ncode\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        XCTAssertEqual(ranges.filter { $0.kind == .codeBlock }.count, 1)
        XCTAssertEqual(ranges.filter { $0.kind == .quoteRun }.count, 1)
    }

    func testDecorationRanges_sortedByLocation() {
        let text = "> quote\n```\ncode\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let locations = ranges.map { $0.range.location }
        XCTAssertEqual(locations, locations.sorted(), "Ranges must be sorted by location")
    }

    func testDecorationRanges_emptyString_producesNoRanges() {
        let ranges = MarkdownDecorationPainter.decorationRanges(in: "")

        XCTAssertTrue(ranges.isEmpty)
    }

    // MARK: - Quote run extent

    func testDecorationRanges_quoteRunSpansFullLineIncludingNewline() {
        let text = "> hello\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let run = ranges.first { $0.kind == .quoteRun }
        XCTAssertNotNil(run)
        // The run should include the trailing newline.
        XCTAssertEqual(NSMaxRange(run!.range), (text as NSString).length)
    }

    // MARK: - Fence exclusion for quote lines (Bug #2)

    func testDecorationRanges_quoteInsideFencedBlock_producesNoQuoteRun() {
        // A `> foo` line inside a fenced code block must NOT produce a .quoteRun decoration —
        // the fence background already covers the block; a bar drawn on top would be spurious.
        let text = "```\n> not a quote\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let quoteRuns = ranges.filter { $0.kind == .quoteRun }
        XCTAssertTrue(quoteRuns.isEmpty,
                      "A `> line` inside a fenced code block must produce no .quoteRun decoration")
    }

    func testDecorationRanges_quoteOutsideAndInsideFence_onlyOutsideQuoteIsDecorated() {
        // A real blockquote before the fence must still produce a .quoteRun; the fake one inside
        // the fence must not.
        let text = "> real quote\n```\n> not a quote\n```\n"
        let ranges = MarkdownDecorationPainter.decorationRanges(in: text)

        let quoteRuns = ranges.filter { $0.kind == .quoteRun }
        XCTAssertEqual(quoteRuns.count, 1,
                       "Only the quote outside the fence block should be decorated")
    }
}
