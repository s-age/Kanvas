import XCTest
@testable import KanvasCore

/// `PaletteColor` enforces two domain rules in its initializer: `colorHex` is validated to a 6-digit
/// "RRGGBB" hex (anything else falls back to `defaultColorHex`), and `label` is truncated to at most
/// `maxLabelLength`. These pin that a hand-edited / corrupt persisted value is re-normalised on load
/// (every entry routes through `init`).
final class PaletteColorTests: XCTestCase {

    func testInit_keepsValidSixDigitHexVerbatim() {
        let color = PaletteColor(colorHex: "1A2B3C")

        XCTAssertEqual(color.colorHex, "1A2B3C")
    }

    func testInit_stripsLeadingHashFromValidHex() {
        let color = PaletteColor(colorHex: "#FF9500")

        XCTAssertEqual(color.colorHex, "FF9500")
    }

    func testInit_emptyHexFallsBackToDefault() {
        let color = PaletteColor(colorHex: "")

        XCTAssertEqual(color.colorHex, PaletteColor.defaultColorHex)
    }

    func testInit_malformedHexFallsBackToDefault() {
        XCTAssertEqual(PaletteColor(colorHex: "ZZZZZZ").colorHex, PaletteColor.defaultColorHex)
        XCTAssertEqual(PaletteColor(colorHex: "FFF").colorHex, PaletteColor.defaultColorHex)
        XCTAssertEqual(PaletteColor(colorHex: "FF9500FF").colorHex, PaletteColor.defaultColorHex)
    }

    func testInit_truncatesLabelToMaxLength() {
        let long = String(repeating: "a", count: PaletteColor.maxLabelLength + 5)

        let color = PaletteColor(colorHex: "000000", label: long)

        XCTAssertEqual(color.label.count, PaletteColor.maxLabelLength)
    }
}
