import XCTest
@testable import KanvasCore

/// `SetConnectorWaypointRequest.validate()` enforces the all-or-nothing offset shape: both axes set
/// (a waypoint), or neither (clear). A half-specified offset is rejected. `validate()` is
/// synchronous, so `XCTAssertThrowsError` applies.
final class SetConnectorWaypointRequestValidationTests: XCTestCase {

    func testBothAxes_passes() throws {
        try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: 3, offsetY: -4).validate()
    }

    func testNeitherAxis_clearsAndPasses() throws {
        try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: nil, offsetY: nil).validate()
    }

    func testXWithoutY_throwsInvalidWaypoint() {
        XCTAssertThrowsError(
            try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: 3, offsetY: nil).validate()
        ) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorWaypoint)
        }
    }

    func testYWithoutX_throwsInvalidWaypoint() {
        XCTAssertThrowsError(
            try SetConnectorWaypointRequest(connectorID: UUID(), offsetX: nil, offsetY: 4).validate()
        ) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorWaypoint)
        }
    }

    func testHasOffset_trueOnlyWhenBothAxesPresent() {
        XCTAssertTrue(SetConnectorWaypointRequest(connectorID: UUID(), offsetX: 1, offsetY: 2).hasOffset)
        XCTAssertFalse(SetConnectorWaypointRequest(connectorID: UUID()).hasOffset)
    }
}
