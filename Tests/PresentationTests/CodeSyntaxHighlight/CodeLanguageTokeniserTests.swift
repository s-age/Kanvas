import XCTest
@testable import KanvasCore

/// Per-language `tokens(in:)` tests for the highlighters under
/// `Views/Markdown/Syntax/Languages/`. Scanner masking / first-wins overlap, the registry, and the
/// `fencedCodeBlocks` / painter / palette resolution live in the sibling files.
final class CodeLanguageTokeniserTests: XCTestCase {

    // MARK: - TypeScript

    func testTypeScript_keywordTokenized() {
        let src = "const x = 1"
        XCTAssertEqual(kinds(of: "const", in: src, TypeScriptHighlighter()), [.keyword])
    }

    func testTypeScript_numberTokenized() {
        let src = "const x = 42"
        XCTAssertEqual(kinds(of: "42", in: src, TypeScriptHighlighter()), [.number])
    }

    func testTypeScript_stringTokenized() {
        let src = "const s = \"hi\""
        XCTAssertEqual(kinds(of: "\"hi\"", in: src, TypeScriptHighlighter()), [.string])
    }

    // MARK: - Swift

    func testSwift_keywordTokenized() {
        let src = "func greet() {}"
        XCTAssertEqual(kinds(of: "func", in: src, SwiftHighlighter()), [.keyword])
    }

    func testSwift_typeTokenized() {
        let src = "let n: Int = 0"
        XCTAssertEqual(kinds(of: "Int", in: src, SwiftHighlighter()), [.type])
    }

    // MARK: - PHP

    func testPHP_variableTokenized() {
        let src = "$name = 1;"
        XCTAssertEqual(kinds(of: "$name", in: src, PHPHighlighter()), [.variable])
    }

    func testPHP_hashCommentTokenized() {
        let src = "# a comment"
        XCTAssertEqual(kinds(of: "# a comment", in: src, PHPHighlighter()), [.comment])
    }

    func testPHP_attributeNotTokenizedAsComment() {
        let src = "#[Route('/api')] public function x() {}"
        XCTAssertFalse(kinds(of: "#[Route", in: src, PHPHighlighter()).contains(.comment))
    }

    func testPHP_keywordAfterAttributeStillTokenized() {
        let src = "#[Route('/api')] public function x() {}"
        XCTAssertEqual(kinds(of: "public", in: src, PHPHighlighter()), [.keyword])
    }

    // MARK: - Shell

    func testShell_variableExpansionTokenized() {
        let src = "echo ${HOME}"
        XCTAssertEqual(kinds(of: "${HOME}", in: src, ShellHighlighter()), [.variable])
    }

    func testShell_keywordTokenized() {
        let src = "if true; then echo hi; fi"
        XCTAssertEqual(kinds(of: "then", in: src, ShellHighlighter()), [.keyword])
    }

    func testShell_startOfLineHashIsComment() {
        // A leading `#` still opens a comment.
        let src = "# a note\necho hi"
        XCTAssertEqual(kinds(of: "# a note", in: src, ShellHighlighter()), [.comment])
    }

    func testShell_hashAfterWhitespaceIsComment() {
        // A `#` following whitespace opens a comment; the boundary char is not part of the token.
        let src = "echo hi # trailing"
        XCTAssertEqual(kinds(of: "# trailing", in: src, ShellHighlighter()), [.comment])
    }

    func testShell_positionalCountParamIsNotComment() {
        // `$#` is the positional-count param: its `#` must NOT open a comment, so the trailing
        // `then`/`echo`/`fi` keep their highlighting. Regression for the round-2 mis-fire.
        let src = "if [ $# -eq 0 ]; then echo hi; fi"
        XCTAssertEqual(kinds(of: "then", in: src, ShellHighlighter()), [.keyword])
    }

    func testShell_positionalCountParamIsVariable() {
        let src = "if [ $# -eq 0 ]; then echo hi; fi"
        XCTAssertEqual(kinds(of: "$#", in: src, ShellHighlighter()), [.variable])
    }

    // MARK: - Mermaid

    func testMermaid_keywordTokenized() {
        let src = "graph TD"
        XCTAssertEqual(kinds(of: "graph", in: src, MermaidHighlighter()), [.keyword])
    }

    func testMermaid_percentCommentTokenized() {
        let src = "%% a note"
        XCTAssertEqual(kinds(of: "%% a note", in: src, MermaidHighlighter()), [.comment])
    }

    // MARK: - Diff (line-oriented)

    func testDiff_addedLineKind() {
        let src = "+added line\n"
        let tokens = DiffHighlighter().tokens(in: src, range: fullRange(src))
        XCTAssertEqual(tokens.map(\.kind), [.diffAdded])
    }

    func testDiff_removedLineKind() {
        let src = "-removed line\n"
        let tokens = DiffHighlighter().tokens(in: src, range: fullRange(src))
        XCTAssertEqual(tokens.map(\.kind), [.diffRemoved])
    }

    func testDiff_hunkHeaderKind() {
        let src = "@@ -1,2 +1,3 @@\n"
        let tokens = DiffHighlighter().tokens(in: src, range: fullRange(src))
        XCTAssertEqual(tokens.map(\.kind), [.diffHunkHeader])
    }

    func testDiff_triplePlusIsMetaNotAdded() {
        let src = "+++ b/file.txt\n"
        let tokens = DiffHighlighter().tokens(in: src, range: fullRange(src))
        XCTAssertEqual(tokens.map(\.kind), [.diffMeta])
    }

    func testDiff_tokenExcludesTrailingNewline() {
        let src = "+added\n"
        let tokens = DiffHighlighter().tokens(in: src, range: fullRange(src))
        XCTAssertEqual(tokens.count, 1)
        XCTAssertEqual(substring(src, tokens[0]), "+added")
    }
}
