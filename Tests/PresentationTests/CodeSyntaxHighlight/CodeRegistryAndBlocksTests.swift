import XCTest
import AppKit
@testable import KanvasCore

/// Tests for the wiring around the per-language highlighters: `CodeHighlighterRegistry` alias
/// resolution, `MarkdownHighlighter.fencedCodeBlocks(in:)` info-string/content extraction, the
/// `styleCodeBlockSyntax` diff line-background range resolution, and `GitHubSyntaxPalette`
/// appearance resolution.
///
/// `@MainActor` because `GitHubSyntaxPalette` and the `MarkdownHighlighter` code-block methods are
/// main-actor.
@MainActor
final class CodeRegistryAndBlocksTests: XCTestCase {

    // MARK: - Registry alias resolution

    func testRegistry_resolvesTypeScriptAlias() {
        XCTAssertTrue(CodeHighlighterRegistry.highlighter(for: "tsx") is TypeScriptHighlighter)
    }

    func testRegistry_resolvesJavaScriptAlias() {
        XCTAssertTrue(CodeHighlighterRegistry.highlighter(for: "javascript") is TypeScriptHighlighter)
    }

    func testRegistry_caseInsensitive() {
        XCTAssertTrue(CodeHighlighterRegistry.highlighter(for: "Swift") is SwiftHighlighter)
    }

    func testRegistry_diffAlias() {
        XCTAssertTrue(CodeHighlighterRegistry.highlighter(for: "patch") is DiffHighlighter)
    }

    func testRegistry_unknownLanguageReturnsNil() {
        XCTAssertNil(CodeHighlighterRegistry.highlighter(for: "cobol"))
    }

    func testRegistry_emptyInfoStringReturnsNil() {
        XCTAssertNil(CodeHighlighterRegistry.highlighter(for: ""))
    }

    // MARK: - fencedCodeBlocks

    func testFencedCodeBlocks_extractsInfoString() {
        let src = "```swift\nlet x = 1\n```\n"
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].infoString, "swift")
    }

    func testFencedCodeBlocks_infoStringLowercased() {
        let src = "```TypeScript\nx\n```\n"
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        XCTAssertEqual(blocks[0].infoString, "typescript")
    }

    func testFencedCodeBlocks_noInfoStringIsEmpty() {
        let src = "```\nplain\n```\n"
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        XCTAssertEqual(blocks[0].infoString, "")
    }

    func testFencedCodeBlocks_contentRangeExcludesFences() {
        let src = "```swift\nlet x = 1\n```\n"
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        let content = (src as NSString).substring(with: blocks[0].contentRange)
        XCTAssertEqual(content, "let x = 1\n")
    }

    func testFencedCodeBlocks_blockRangeMatchesLegacyRanges() {
        // The new resolver's blockRange must equal the legacy `fencedCodeBlockRanges` output.
        let src = "intro\n```swift\nlet x = 1\n```\nafter\n"
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        let legacy = MarkdownHighlighter.fencedCodeBlockRanges(in: src)
        XCTAssertEqual(blocks.map(\.blockRange), legacy)
    }

    // MARK: - styleCodeBlockSyntax + diff line backgrounds

    func testStyleCodeBlockSyntax_appliesDiffLineKindAttribute() {
        let src = "```diff\n+added\n-removed\n```\n"
        let storage = NSTextStorage(string: src)
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        MarkdownHighlighter.styleCodeBlockSyntax(storage, in: src, blocks: blocks, theme: .default)

        let backgrounds = MarkdownDecorationPainter.diffLineBackgroundRanges(in: storage)
        XCTAssertEqual(backgrounds.map(\.kind), [.added, .removed])
    }

    func testStyleCodeBlockSyntax_keywordUsesThemeSyntaxColor() {
        let src = "```swift\nfunc x() {}\n```\n"
        let storage = NSTextStorage(string: src)
        let blocks = MarkdownHighlighter.fencedCodeBlocks(in: src)
        MarkdownHighlighter.styleCodeBlockSyntax(storage, in: src, blocks: blocks, theme: .default)

        // `func` is a keyword — its foreground should be the resolved keyword colour, not the base.
        let funcRange = (src as NSString).range(of: "func")
        let applied = storage.attribute(.foregroundColor, at: funcRange.location,
                                        effectiveRange: nil) as? NSColor
        XCTAssertEqual(applied, MarkdownTheme.default.syntaxColors[.keyword])
    }

    func testDiffLineBackgroundRanges_emptyWithoutDiffAttributes() {
        let storage = NSTextStorage(string: "plain text")
        XCTAssertTrue(MarkdownDecorationPainter.diffLineBackgroundRanges(in: storage).isEmpty)
    }

    // MARK: - GitHubSyntaxPalette built-in resolution (no overrides)

    func testPalette_keywordResolvesLightAndDark() {
        let color = GitHubSyntaxPalette.resolvedColors(overrides: [:])[.keyword]
        XCTAssertEqual(color?.hex(in: .aqua), "cf222e")
        XCTAssertEqual(color?.hex(in: .darkAqua), "ff7b72")
    }

    func testPalette_diffAddedLineBackgroundResolves() {
        let bg = GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: [:])[.diffAdded]
        XCTAssertNotNil(bg)
        XCTAssertEqual(bg?.hex(in: .aqua), "e6ffec")
        XCTAssertEqual(bg?.hex(in: .darkAqua), "033a16")
    }

    func testPalette_noLineBackgroundForKeyword() {
        XCTAssertNil(GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: [:])[.keyword])
    }

    func testPalette_hunkHeaderIsBold() {
        XCTAssertTrue(GitHubSyntaxPalette.isBold(.diffHunkHeader))
        XCTAssertFalse(GitHubSyntaxPalette.isBold(.keyword))
    }

    // MARK: - GitHubSyntaxPalette settings overrides

    func testResolvedColors_overrideReplacesKeywordColour() {
        let override: [CodeTokenKind: NSColor] = [.keyword: NSColor(hex: "123456")]
        let resolved = GitHubSyntaxPalette.resolvedColors(overrides: override)
        XCTAssertEqual(resolved[.keyword]?.hex(in: .aqua), "123456")
    }

    func testResolvedColors_absentKindKeepsBuiltIn() {
        let override: [CodeTokenKind: NSColor] = [.keyword: NSColor(hex: "123456")]
        let resolved = GitHubSyntaxPalette.resolvedColors(overrides: override)
        // `.string` was not overridden — it keeps the built-in Primer colour.
        XCTAssertEqual(resolved[.string]?.hex(in: .aqua), "0a3069")
    }

    func testResolvedLineBackgrounds_overrideReplacesDiffAdded() {
        let override: [CodeTokenKind: NSColor] = [.diffAdded: NSColor(hex: "abcdef")]
        let resolved = GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: override)
        XCTAssertEqual(resolved[.diffAdded]?.hex(in: .aqua), "abcdef")
    }

    // MARK: - CodeTokenKind override key resolution

    func testResolveOverrides_mapsKnownKeyToColour() {
        let resolved = CodeTokenKind.resolveOverrides(["keyword": "00ff00"])
        XCTAssertEqual(resolved[.keyword]?.hex(in: .aqua), "00ff00")
    }

    func testResolveOverrides_dropsUnknownKey() {
        let resolved = CodeTokenKind.resolveOverrides(["bogus": "00ff00"])
        XCTAssertTrue(resolved.isEmpty)
    }

    func testThemeSyntaxColors_reflectSettingsOverride() {
        let settings = MarkdownSettingsResponse(
            MarkdownSettings(syntaxColorOverrides: ["keyword": "654321"])
        )
        let theme = MarkdownTheme(settings: settings, global: nil)
        XCTAssertEqual(theme.syntaxColors[.keyword]?.hex(in: .aqua), "654321")
    }
}
