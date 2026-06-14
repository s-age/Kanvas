import XCTest
@testable import KanvasCore

/// `AddShapeRequest.validate()` checks that `kind` is non-empty and `topology` is a known
/// behaviour class. The open kind token ("triangle", etc.) is accepted — only empty is rejected.
final class AddShapeRequestValidationTests: XCTestCase {

    private func request(kind: String, topology: String = "box") -> AddShapeRequest {
        AddShapeRequest(cardID: UUID(), kind: kind, topology: topology,
                        positionX: 0, positionY: 0, width: 100, height: 80)
    }

    func testValidate_emptyKind_throwsInvalidShapeKind() {
        XCTAssertThrowsError(try request(kind: "").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidShapeKind)
        }
    }

    func testValidate_unknownTopology_throwsInvalidShapeTopology() {
        XCTAssertThrowsError(try request(kind: "triangle", topology: "circle").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidShapeTopology)
        }
    }

    func testValidate_openKindWithBoxTopology_passes() throws {
        try request(kind: "triangle", topology: "box").validate()
    }

    func testValidate_knownKindWithSegmentTopology_passes() throws {
        try request(kind: "line", topology: "segment").validate()
    }
}
