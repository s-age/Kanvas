import XCTest
@testable import KanvasCore

/// Label requests enforce a non-empty (post-trim) name and a 6-digit RGB hex colour, since the
/// colour drives canvas drawing directly. `validate()` is synchronous, so `XCTAssertThrowsError`
/// applies.
final class LabelValidationTests: XCTestCase {

    func testValidate_validNameAndColor_passes() throws {
        try AddLabelRequest(name: "UI", colorHex: "FF9500").validate()
    }

    func testValidate_blankName_throwsEmptyLabelName() {
        XCTAssertThrowsError(try AddLabelRequest(name: "   ", colorHex: "FF9500").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .emptyLabelName)
        }
    }

    func testValidate_shortHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try AddLabelRequest(name: "UI", colorHex: "FFF").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    func testValidate_nonHexCharacter_throwsInvalidColorHex() {
        XCTAssertThrowsError(try AddLabelRequest(name: "UI", colorHex: "GGGGGG").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    func testValidate_editRequestBlankName_throwsEmptyLabelName() {
        let request = EditLabelRequest(labelID: UUID(), name: "", colorHex: "000000")
        XCTAssertThrowsError(try request.validate()) { error in
            XCTAssertEqual(error as? ValidationError, .emptyLabelName)
        }
    }
}
