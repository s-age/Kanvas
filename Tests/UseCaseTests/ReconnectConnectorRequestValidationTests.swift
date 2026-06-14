import XCTest
@testable import KanvasCore

/// `ReconnectConnectorRequest.validate()` enforces the endpoint-edit shape: each side is
/// all-or-nothing (both stickyID and edge, or neither), at least one side is present, and any
/// provided edge resolves to a `CanvasEdge`. `validate()` is synchronous, so `XCTAssertThrowsError`
/// applies. The self-loop rule needs the connector's other live endpoint, so it is a domain check
/// (see `ConnectorServiceTests`), not validated here.
final class ReconnectConnectorRequestValidationTests: XCTestCase {

    func testSourceOnly_fullySpecified_passes() throws {
        try ReconnectConnectorRequest(
            connectorID: UUID(), sourceStickyID: UUID(), sourceEdge: "top"
        ).validate()
    }

    func testTargetOnly_fullySpecified_passes() throws {
        try ReconnectConnectorRequest(
            connectorID: UUID(), targetStickyID: UUID(), targetEdge: "left"
        ).validate()
    }

    func testBothSides_fullySpecified_passes() throws {
        try ReconnectConnectorRequest(
            connectorID: UUID(),
            sourceStickyID: UUID(), sourceEdge: "right",
            targetStickyID: UUID(), targetEdge: "bottom"
        ).validate()
    }

    func testSourceStickyWithoutEdge_throwsInvalidEdge() {
        XCTAssertThrowsError(try ReconnectConnectorRequest(
            connectorID: UUID(), sourceStickyID: UUID(), sourceEdge: nil
        ).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorEdge)
        }
    }

    func testSourceEdgeWithoutSticky_throwsInvalidEdge() {
        XCTAssertThrowsError(try ReconnectConnectorRequest(
            connectorID: UUID(), sourceStickyID: nil, sourceEdge: "top"
        ).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorEdge)
        }
    }

    func testBothSidesNil_throwsInvalidEdge() {
        XCTAssertThrowsError(try ReconnectConnectorRequest(connectorID: UUID()).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorEdge)
        }
    }

    func testInvalidEdgeRawValue_throwsInvalidEdge() {
        XCTAssertThrowsError(try ReconnectConnectorRequest(
            connectorID: UUID(), targetStickyID: UUID(), targetEdge: "sideways"
        ).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidConnectorEdge)
        }
    }
}
