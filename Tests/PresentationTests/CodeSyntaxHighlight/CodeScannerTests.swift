import XCTest
@testable import KanvasCore

/// Tests for the shared, language-agnostic `CodeScanner`: comment/string masking (phase 1) and the
/// phase-2 first-wins overlap resolution between the keyword / function / variable rules.
final class CodeScannerTests: XCTestCase {

    // MARK: - CodeScanner masking

    func testScanner_keywordInsideStringNotColored() {
        // "const" appears inside a string literal and must NOT be coloured as a keyword.
        let src = "let s = \"const here\""
        let tokens = SwiftHighlighter().tokens(in: src, range: fullRange(src))
        let target = (src as NSString).range(of: "const")
        let inside = tokens.filter { NSIntersectionRange($0.range, target).length > 0 }
        XCTAssertEqual(inside.map(\.kind), [.string],
                       "keyword inside a string must be masked, leaving only the string token")
    }

    func testScanner_keywordInsideCommentNotColored() {
        let src = "// return value\nlet x = 1"
        let tokens = SwiftHighlighter().tokens(in: src, range: fullRange(src))
        let target = (src as NSString).range(of: "return")
        let inside = tokens.filter { NSIntersectionRange($0.range, target).length > 0 }
        XCTAssertEqual(inside.map(\.kind), [.comment])
    }

    // MARK: - First-wins overlap (keyword vs function rule)

    func testSwift_controlKeywordBeforeParenIsKeywordNotFunction() {
        // `if (` matches both the keyword rule and the shared `\w+(?=\s*\()` function rule.
        // The keyword rule is listed first, so first-wins must leave ONLY a keyword token.
        let src = "if (x) {}"
        let tokens = SwiftHighlighter().tokens(in: src, range: fullRange(src))
        let target = (src as NSString).range(of: "if")
        let inside = tokens.filter { NSIntersectionRange($0.range, target).length > 0 }
        XCTAssertEqual(inside.map(\.kind), [.keyword],
                       "a control keyword before `(` must stay a keyword, not a function")
    }

    func testTypeScript_forKeywordBeforeParenIsKeywordNotFunction() {
        let src = "for (i) {}"
        XCTAssertEqual(kinds(of: "for", in: src, TypeScriptHighlighter()), [.keyword])
    }

    func testPHP_ifKeywordBeforeParenIsKeywordNotFunction() {
        let src = "if ($x) {}"
        XCTAssertEqual(kinds(of: "if", in: src, PHPHighlighter()), [.keyword])
    }

    func testSwift_genuineFunctionCallStillTokenized() {
        // A non-keyword identifier before `(` must still be a function — first-wins must not
        // suppress legitimate function tokens.
        let src = "greet(name)"
        XCTAssertEqual(kinds(of: "greet", in: src, SwiftHighlighter()), [.function])
    }

    func testShell_dollarSetIsVariableNotKeyword() {
        // `$set` matches the `.variable` rule (listed first) and the `set` keyword. First-wins
        // must keep the whole `$set` as a single variable token.
        let src = "echo $set"
        let tokens = ShellHighlighter().tokens(in: src, range: fullRange(src))
        let target = (src as NSString).range(of: "$set")
        let inside = tokens.filter { NSIntersectionRange($0.range, target).length > 0 }
        XCTAssertEqual(inside.map(\.kind), [.variable],
                       "a `$VAR` whose name equals a keyword must stay a single variable token")
    }
}
