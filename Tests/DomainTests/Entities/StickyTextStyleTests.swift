import XCTest
@testable import KanvasCore

/// `StickyTextStyle.init` normalises its inputs (domain rules): the retired `"auto"` sentinel is
/// coerced to the concrete default colour, and `fontSize` is clamped. These pin that a legacy or
/// hand-edited persisted value is re-validated on construction (the "untrusted input" rule), so the
/// mapper can pass stored values straight through.
final class StickyTextStyleTests: XCTestCase {

    func testInit_coercesAutoSentinelToDefaultColor() {
        XCTAssertEqual(StickyTextStyle(colorHex: "auto").colorHex, StickyTextStyle.defaultColorHex)
    }

    func testInit_coercesAutoSentinelCaseInsensitively() {
        XCTAssertEqual(StickyTextStyle(colorHex: "AUTO").colorHex, StickyTextStyle.defaultColorHex)
    }

    func testInit_keepsConcreteColorVerbatim() {
        XCTAssertEqual(StickyTextStyle(colorHex: "FF0000").colorHex, "FF0000")
    }

    func testInit_clampsFontSize() {
        XCTAssertEqual(StickyTextStyle(fontSize: 999).fontSize, StickyTextStyle.maxFontSize)
        XCTAssertEqual(StickyTextStyle(fontSize: 0).fontSize, StickyTextStyle.minFontSize)
    }

    func testCanvasSettingsInit_coercesAutoDefaultTextColor() {
        XCTAssertEqual(
            CanvasSettings(defaultTextColorHex: "auto").defaultTextColorHex,
            StickyTextStyle.defaultColorHex
        )
    }
}
