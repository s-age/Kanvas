import XCTest
@testable import KanvasMCP
import KanvasCore
import MCP

/// Pins the pure argument-decoding contracts of the `canvas_connector_*` tools:
/// `Arguments.optionalDouble` and the either/or drop-frame derivation in `connectorDropFrame`.
final class ConnectorArgumentTests: XCTestCase {

    // MARK: - Arguments.optionalDouble

    func testOptionalDouble_absentKey_returnsNil() throws {
        XCTAssertNil(try Arguments([:]).optionalDouble("x"))
    }

    func testOptionalDouble_jsonNull_returnsNil() throws {
        XCTAssertNil(try Arguments(["x": .null]).optionalDouble("x"))
    }

    func testOptionalDouble_double_returnsValue() throws {
        XCTAssertEqual(try Arguments(["x": .double(1.5)]).optionalDouble("x"), 1.5)
    }

    func testOptionalDouble_int_coercesToDouble() throws {
        XCTAssertEqual(try Arguments(["x": .int(3)]).optionalDouble("x"), 3.0)
    }

    func testOptionalDouble_wrongType_throwsInsteadOfDroppingSilently() {
        XCTAssertThrowsError(try Arguments(["x": .string("12")]).optionalDouble("x"))
    }

    // MARK: - connectorDropFrame (either/or shape of canvas_connector_add)

    func testDropFrame_targetGiven_isNilEvenWithCoordinates() throws {
        let args = Arguments(["x": .double(10), "y": .double(20)])
        XCTAssertNil(try connectorDropFrame(args, hasTarget: true))
    }

    func testDropFrame_noTargetNoCoordinates_isNil() throws {
        // nil (not a throw): the gateway then raises missingConnectorTarget, whose message
        // explains both the targetStickyID and the x/y option.
        XCTAssertNil(try connectorDropFrame(Arguments([:]), hasTarget: false))
    }

    func testDropFrame_bothCoordinates_buildsFrameWithDefaultSize() throws {
        let frame = try connectorDropFrame(Arguments(["x": .double(300), "y": .double(400)]), hasTarget: false)
        XCTAssertEqual(frame?.x, 300)
        XCTAssertEqual(frame?.y, 400)
        XCTAssertEqual(frame?.width, 200)   // app's grow-gesture default
        XCTAssertEqual(frame?.height, 150)
    }

    func testDropFrame_explicitSize_overridesDefaults() throws {
        let args = Arguments(["x": .double(0), "y": .double(0), "width": .double(320), "height": .double(90)])
        let frame = try connectorDropFrame(args, hasTarget: false)
        XCTAssertEqual(frame?.width, 320)
        XCTAssertEqual(frame?.height, 90)
    }

    func testDropFrame_oneCoordinateOnly_throwsNamingTheMissingOne() {
        // The model committed to the drop branch, so the error names exactly the forgotten key.
        XCTAssertThrowsError(try connectorDropFrame(Arguments(["y": .double(5)]), hasTarget: false)) { error in
            XCTAssertEqual(String(describing: error), "Missing required argument: x")
        }
        XCTAssertThrowsError(try connectorDropFrame(Arguments(["x": .double(5)]), hasTarget: false)) { error in
            XCTAssertEqual(String(describing: error), "Missing required argument: y")
        }
    }

    func testDropFrame_zeroCoordinates_stillCountAsProvided() throws {
        // 0 is a legitimate canvas coordinate — `.some(0.0)` must not read as "absent".
        let frame = try connectorDropFrame(Arguments(["x": .double(0), "y": .double(0)]), hasTarget: false)
        XCTAssertEqual(frame?.x, 0)
        XCTAssertEqual(frame?.y, 0)
    }

    // MARK: - connectorEndpointArg (each reconnect side is all-or-nothing)

    func testEndpointArg_bothOmitted_isNil() throws {
        // An omitted side means "keep this endpoint" — nil, not an error.
        XCTAssertNil(try connectorEndpointArg(Arguments([:]), stickyKey: "sourceStickyID",
                                              edgeKey: "sourceEdge", side: "source"))
    }

    func testEndpointArg_bothPresent_buildsArg() throws {
        let args = Arguments(["sourceStickyID": .string("abc"), "sourceEdge": .string("top")])
        let arg = try connectorEndpointArg(args, stickyKey: "sourceStickyID", edgeKey: "sourceEdge", side: "source")
        XCTAssertEqual(arg?.stickyID, "abc")
        XCTAssertEqual(arg?.edge, "top")
    }

    func testEndpointArg_stickyWithoutEdge_throwsHalfSpecified() {
        // r1-3: a half-specified side must be rejected here, naming both keys — not forwarded.
        let args = Arguments(["sourceStickyID": .string("abc")])
        XCTAssertThrowsError(
            try connectorEndpointArg(args, stickyKey: "sourceStickyID", edgeKey: "sourceEdge", side: "source")
        ) { error in
            guard case KanvasMCPError.halfSpecifiedConnectorSide(let side) = error else {
                return XCTFail("Expected halfSpecifiedConnectorSide, got \(error)")
            }
            XCTAssertEqual(side, "source")
        }
    }

    func testEndpointArg_edgeWithoutSticky_throwsHalfSpecifiedNotEmptyUUID() {
        // r1-3: edge-without-stickyID used to forward stickyID "" and surface a confusing
        // badUUID(value: "") downstream. It must now be rejected as a half-specified side instead.
        let args = Arguments(["targetEdge": .string("left")])
        XCTAssertThrowsError(
            try connectorEndpointArg(args, stickyKey: "targetStickyID", edgeKey: "targetEdge", side: "target")
        ) { error in
            guard case KanvasMCPError.halfSpecifiedConnectorSide(let side) = error else {
                return XCTFail("Expected halfSpecifiedConnectorSide, got \(error)")
            }
            XCTAssertEqual(side, "target")
        }
    }
}
