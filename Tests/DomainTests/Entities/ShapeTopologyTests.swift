import XCTest
@testable import KanvasCore

/// `ShapeTopology` raw-value contract (persistence) and `inferred(fromKind:)` back-compat
/// helper. These pin the on-disk encoding — a raw-value rename silently breaks all existing
/// snapshots, so they are asserted concretely.
final class ShapeTopologyTests: XCTestCase {

    // MARK: - inferred(fromKind:)

    func testInferred_lineKind_returnsSegment() {
        XCTAssertEqual(ShapeTopology.inferred(fromKind: "line"), .segment)
    }

    func testInferred_rectangleKind_returnsBox() {
        XCTAssertEqual(ShapeTopology.inferred(fromKind: "rectangle"), .box)
    }

    func testInferred_triangleKind_returnsBox() {
        XCTAssertEqual(ShapeTopology.inferred(fromKind: "triangle"), .box)
    }

    func testInferred_emptyKind_returnsBox() {
        XCTAssertEqual(ShapeTopology.inferred(fromKind: ""), .box)
    }

    // MARK: - rawValue (persistence contract)

    func testRawValue_boxDecodes() {
        XCTAssertEqual(ShapeTopology(rawValue: "box"), .box)
    }

    func testRawValue_segmentDecodes() {
        XCTAssertEqual(ShapeTopology(rawValue: "segment"), .segment)
    }

    func testRawValue_circleIsNil() {
        XCTAssertNil(ShapeTopology(rawValue: "circle"))
    }
}
