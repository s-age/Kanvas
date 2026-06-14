import XCTest
@testable import KanvasCore

/// The numeric setter requests (sticky font size, connector/shape stroke width) reject input outside
/// their domain bounds — the same `[min, max]` their entity initializers clamp to — so a boundary-less
/// MCP caller is told off rather than silently clamped. The range check also rejects non-finite input
/// (NaN/Inf fail the compares). `validate()` is synchronous, so `XCTAssertThrowsError` applies.
final class NumericSetterRequestValidationTests: XCTestCase {

    // MARK: - SetStickyFontSizeRequest

    func testFontSize_inRange_passes() throws {
        try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: StickyTextStyle.defaultFontSize).validate()
    }

    func testFontSize_atBounds_passes() throws {
        try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: StickyTextStyle.minFontSize).validate()
        try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: StickyTextStyle.maxFontSize).validate()
    }

    func testFontSize_zero_throwsOutOfRange() {
        XCTAssertThrowsError(try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: 0).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    func testFontSize_negative_throwsOutOfRange() {
        XCTAssertThrowsError(try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: -5).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    func testFontSize_aboveMax_throwsOutOfRange() {
        XCTAssertThrowsError(try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: 1000).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    func testFontSize_nan_throwsOutOfRange() {
        XCTAssertThrowsError(try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: .nan).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    func testFontSize_infinity_throwsOutOfRange() {
        XCTAssertThrowsError(try SetStickyFontSizeRequest(stickyID: UUID(), fontSize: .infinity).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .fontSizeOutOfRange(
                min: StickyTextStyle.minFontSize, max: StickyTextStyle.maxFontSize
            ))
        }
    }

    // MARK: - SetConnectorStrokeWidthRequest

    func testConnectorWidth_inRange_passes() throws {
        try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: ConnectorStyle.defaultStrokeWidth).validate()
    }

    func testConnectorWidth_atBounds_passes() throws {
        try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: ConnectorStyle.minStrokeWidth).validate()
        try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: ConnectorStyle.maxStrokeWidth).validate()
    }

    func testConnectorWidth_zero_throwsOutOfRange() {
        XCTAssertThrowsError(try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: 0).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    func testConnectorWidth_aboveMax_throwsOutOfRange() {
        XCTAssertThrowsError(try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: 1000).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    func testConnectorWidth_infinity_throwsOutOfRange() {
        XCTAssertThrowsError(try SetConnectorStrokeWidthRequest(connectorID: UUID(), width: .infinity).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    // MARK: - SetShapeStrokeWidthRequest

    func testShapeWidth_inRange_passes() throws {
        try SetShapeStrokeWidthRequest(shapeID: UUID(), width: CanvasShapeStyle.defaultStrokeWidth).validate()
    }

    func testShapeWidth_atBounds_passes() throws {
        try SetShapeStrokeWidthRequest(shapeID: UUID(), width: CanvasShapeStyle.minStrokeWidth).validate()
        try SetShapeStrokeWidthRequest(shapeID: UUID(), width: CanvasShapeStyle.maxStrokeWidth).validate()
    }

    func testShapeWidth_negative_throwsOutOfRange() {
        XCTAssertThrowsError(try SetShapeStrokeWidthRequest(shapeID: UUID(), width: -1).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: CanvasShapeStyle.minStrokeWidth, max: CanvasShapeStyle.maxStrokeWidth
            ))
        }
    }

    func testShapeWidth_nan_throwsOutOfRange() {
        XCTAssertThrowsError(try SetShapeStrokeWidthRequest(shapeID: UUID(), width: .nan).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: CanvasShapeStyle.minStrokeWidth, max: CanvasShapeStyle.maxStrokeWidth
            ))
        }
    }

    // MARK: - SetConnectorStyleRequest (bundled MCP edit path)

    private func styleRequest(strokeWidth: Double?) -> SetConnectorStyleRequest {
        SetConnectorStyleRequest(
            connectorID: UUID(), cap: nil, routing: nil, strokeColorHex: nil, strokeWidth: strokeWidth
        )
    }

    func testStyleStrokeWidth_nil_passes() throws {
        try styleRequest(strokeWidth: nil).validate()
    }

    func testStyleStrokeWidth_inRange_passes() throws {
        try styleRequest(strokeWidth: ConnectorStyle.defaultStrokeWidth).validate()
    }

    func testStyleStrokeWidth_outOfRange_throwsOutOfRange() {
        XCTAssertThrowsError(try styleRequest(strokeWidth: 1000).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }

    func testStyleStrokeWidth_nan_throwsOutOfRange() {
        XCTAssertThrowsError(try styleRequest(strokeWidth: .nan).validate()) { error in
            XCTAssertEqual(error as? ValidationError, .strokeWidthOutOfRange(
                min: ConnectorStyle.minStrokeWidth, max: ConnectorStyle.maxStrokeWidth
            ))
        }
    }
}
