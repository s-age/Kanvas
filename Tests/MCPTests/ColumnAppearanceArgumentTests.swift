import XCTest
@testable import KanvasMCP
import KanvasCore
import MCP

/// Pins `Arguments.optionalBool`, the decoder `board_column_appearance_edit` uses for its
/// `isCompletionColumn` flag. Same loud-failure contract as `optionalString`/`optionalDouble`:
/// absent/null → nil (keep), a real bool → the value, a mistyped value → throw (never a silent drop
/// that would make the model believe the flag was applied).
final class ColumnAppearanceArgumentTests: XCTestCase {

    func testOptionalBool_absentKey_returnsNil() throws {
        XCTAssertNil(try Arguments([:]).optionalBool("isCompletionColumn"))
    }

    func testOptionalBool_jsonNull_returnsNil() throws {
        XCTAssertNil(try Arguments(["isCompletionColumn": .null]).optionalBool("isCompletionColumn"))
    }

    func testOptionalBool_true_returnsTrue() throws {
        XCTAssertEqual(try Arguments(["isCompletionColumn": .bool(true)]).optionalBool("isCompletionColumn"), true)
    }

    func testOptionalBool_false_returnsFalse() throws {
        XCTAssertEqual(try Arguments(["isCompletionColumn": .bool(false)]).optionalBool("isCompletionColumn"), false)
    }

    func testOptionalBool_wrongType_throwsInsteadOfDroppingSilently() {
        XCTAssertThrowsError(try Arguments(["isCompletionColumn": .string("true")]).optionalBool("isCompletionColumn"))
    }
}
