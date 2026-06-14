import XCTest
@testable import KanvasCore

/// Sticky colour requests enforce the 6-digit RGB hex format (mirroring the shape/label flow), since
/// the colour drives canvas drawing directly. Text colour is required; fill colour (set and add
/// paths) additionally accepts `nil` (inherit the board default). `validate()` is synchronous, so
/// `XCTAssertThrowsError` applies. These pin the `if let` pass-side branches that the wiring tests
/// (which only feed invalid input) cannot reach.
final class SetStickyColorRequestValidationTests: XCTestCase {

    // MARK: - SetStickyTextColorRequest

    func testTextColor_validHex_passes() throws {
        try SetStickyTextColorRequest(stickyID: UUID(), colorHex: "00FF88").validate()
    }

    func testTextColor_invalidHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try SetStickyTextColorRequest(stickyID: UUID(), colorHex: "GGGGGG").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    // MARK: - SetStickyFillColorRequest

    func testFillColor_nil_passes() throws {
        try SetStickyFillColorRequest(stickyID: UUID(), fillColorHex: nil).validate()
    }

    func testFillColor_validHex_passes() throws {
        try SetStickyFillColorRequest(stickyID: UUID(), fillColorHex: "00FF88").validate()
    }

    func testFillColor_invalidHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try SetStickyFillColorRequest(stickyID: UUID(), fillColorHex: "GGGGGG").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    // MARK: - AddStickyRequest fill colour

    func testAddStickyFill_nil_passes() throws {
        try makeAddSticky(fillColorHex: nil).validate()
    }

    func testAddStickyFill_validHex_passes() throws {
        try makeAddSticky(fillColorHex: "00FF88").validate()
    }

    func testAddStickyFill_invalidHex_throwsInvalidColorHex() {
        XCTAssertThrowsError(try makeAddSticky(fillColorHex: "GGGGGG").validate()) { error in
            XCTAssertEqual(error as? ValidationError, .invalidColorHex)
        }
    }

    private func makeAddSticky(fillColorHex: String?) -> AddStickyRequest {
        AddStickyRequest(
            cardID: UUID(), content: "",
            positionX: 0, positionY: 0, width: 100, height: 100,
            fillColorHex: fillColorHex
        )
    }
}
