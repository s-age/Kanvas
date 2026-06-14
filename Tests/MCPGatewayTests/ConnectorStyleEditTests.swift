import XCTest
@testable import KanvasCore

/// Pins `ConnectorStyleEdit.isEmpty` — the gateway's emptyConnectorEdit guard keys off it, so a
/// drifted definition would either reject real edits or let an all-nil no-op echo as a success.
final class ConnectorStyleEditTests: XCTestCase {

    func testIsEmpty_trueOnlyWhenEveryFieldIsNil() {
        XCTAssertTrue(ConnectorStyleEdit(cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: nil).isEmpty)
    }

    func testIsEmpty_falseWhenAnySingleFieldIsSet() {
        XCTAssertFalse(ConnectorStyleEdit(cap: "arrow", routing: nil, strokeColorHex: nil, strokeWidth: nil).isEmpty)
        XCTAssertFalse(ConnectorStyleEdit(cap: nil, routing: "elbow", strokeColorHex: nil, strokeWidth: nil).isEmpty)
        XCTAssertFalse(ConnectorStyleEdit(cap: nil, routing: nil, strokeColorHex: "000000", strokeWidth: nil).isEmpty)
        XCTAssertFalse(ConnectorStyleEdit(cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: 2).isEmpty)
    }
}
