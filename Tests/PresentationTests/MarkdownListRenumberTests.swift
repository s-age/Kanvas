import XCTest
@testable import KanvasCore

/// `MarkdownListRenumber.computeEdits` is the pure, off-by-one-prone core that keeps ordered
/// Markdown lists sequential per contiguous list and indent level. These tests exercise it
/// directly (no `NSTextView`) by applying the returned edits and asserting the resulting text.
@MainActor
final class MarkdownListRenumberTests: XCTestCase {

    /// Applies the computed renumber edits to `input`, yielding the corrected document.
    private func renumbered(_ input: String) -> String {
        let result = NSMutableString(string: input)
        for edit in MarkdownListRenumber.computeEdits(input as NSString)
            .sorted(by: { $0.range.location > $1.range.location }) {
            result.replaceCharacters(in: edit.range, with: edit.replacement)
        }
        return result as String
    }

    // MARK: - No-op

    func testComputeEdits_alreadySequential_producesNoEdits() {
        XCTAssertEqual(MarkdownListRenumber.computeEdits("1. a\n2. b\n3. c" as NSString), [])
    }

    func testRenumber_bullets_areLeftUntouched() {
        XCTAssertEqual(renumbered("- a\n- b\n- c"), "- a\n- b\n- c")
    }

    // MARK: - Sequential repair

    func testRenumber_gapsFromDeletion_compactToSequential() {
        XCTAssertEqual(renumbered("1. a\n3. b\n4. c"), "1. a\n2. b\n3. c")
    }

    func testRenumber_wrongFirstNumber_resetsToOne() {
        XCTAssertEqual(renumbered("5. a\n6. b"), "1. a\n2. b")
    }

    // MARK: - Nesting

    func testRenumber_indentedChild_restartsAtOne() {
        XCTAssertEqual(renumbered("1. a\n    5. b\n2. c"), "1. a\n    1. b\n2. c")
    }

    func testRenumber_returnToParentLevel_continuesParentSequence() {
        XCTAssertEqual(
            renumbered("1. x\n    1. y\n    3. z\n2. w"),
            "1. x\n    1. y\n    2. z\n2. w"
        )
    }

    // MARK: - List boundaries

    func testRenumber_blankLine_startsAFreshList() {
        XCTAssertEqual(renumbered("1. a\n2. b\n\n5. c"), "1. a\n2. b\n\n1. c")
    }

    func testRenumber_nonListLine_breaksTheList() {
        XCTAssertEqual(renumbered("1. a\nplain text\n4. b"), "1. a\nplain text\n1. b")
    }

    func testRenumber_bulletAtSameLevel_restartsFollowingOrdered() {
        XCTAssertEqual(renumbered("- a\n3. b\n4. c"), "- a\n1. b\n2. c")
    }
}
