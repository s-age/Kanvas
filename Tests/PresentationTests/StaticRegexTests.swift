import XCTest
@testable import KanvasCore

/// Tests for the shared `StaticRegex.compile` helper that backs every compile-time-constant regex in
/// the Markdown highlighting / code-scanning code (replacing the per-site `try!` + `force_try`
/// disables for `MarkdownHighlighter.Patterns` and `CodeRule`).
final class StaticRegexTests: XCTestCase {

    func testCompile_validPattern_returnsCompiledRegex() {
        let regex = StaticRegex.compile("ab+c")
        let str = "xabbbcy"
        let match = regex.firstMatch(in: str, range: NSRange(location: 0, length: (str as NSString).length))
        XCTAssertEqual(match?.range, NSRange(location: 1, length: 5))
    }

    func testCompile_defaultOptions_anchorMatchesWholeStringOnly() {
        // With no options, `^`/`$` anchor the whole string, so a mid-text line start does NOT match.
        let regex = StaticRegex.compile("^line$")
        let str = "first\nline"
        let count = regex.numberOfMatches(
            in: str, range: NSRange(location: 0, length: (str as NSString).length))
        XCTAssertEqual(count, 0, "default (no anchorsMatchLines) must not anchor at the second line")
    }

    func testCompile_anchorsMatchLinesOption_anchorsEachLine() {
        // With `.anchorsMatchLines`, `^`/`$` anchor each line, so the second line matches.
        let regex = StaticRegex.compile("^line$", options: [.anchorsMatchLines])
        let str = "first\nline"
        let count = regex.numberOfMatches(
            in: str, range: NSRange(location: 0, length: (str as NSString).length))
        XCTAssertEqual(count, 1, ".anchorsMatchLines must anchor `$` at the second line")
    }
}
