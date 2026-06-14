import XCTest
@testable import KanvasCore

/// Shape colour requests enforce the 6-digit RGB hex format (mirroring the label flow), since the
/// colour drives canvas drawing directly. Fill additionally accepts `nil` (no fill). `validate()`
/// is synchronous, so `XCTAssertThrowsError` applies.
final class SetShapeColorRequestValidationTests: XCTestCase {

    func testStrokeColor_validHex_passes() throws {
        try SetShapeStrokeColorRequest(shapeID: UUID(), colorHex: "FF9500").validate()
    }

    func testStrokeColor_invalidHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try SetShapeStrokeColorRequest(shapeID: UUID(), colorHex: "nope").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    func testFillColor_nil_passes() throws {
        try SetShapeFillColorRequest(shapeID: UUID(), colorHex: nil).validate()
    }

    func testFillColor_invalidHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try SetShapeFillColorRequest(shapeID: UUID(), colorHex: "FFF").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }
}
