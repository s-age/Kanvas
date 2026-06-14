import XCTest
@testable import KanvasCore

/// `ContrastColor.readableHex(onBackground:)` picks the canvas's #333 / #ddd foreground from a
/// background's perceptual luminance — the single Domain source shared by the sticky-text and
/// connector-stroke auto-contrast. Pins the light/dark split, the `#`/lowercase tolerance, and the
/// malformed-input fallback to on-light.
final class ContrastColorTests: XCTestCase {

    func testReadableHex_darkBackground_picksOnDark() {
        XCTAssertEqual(ContrastColor.readableHex(onBackground: "333333"), ContrastColor.onDarkHex)
    }

    func testReadableHex_lightBackground_picksOnLight() {
        XCTAssertEqual(ContrastColor.readableHex(onBackground: "FFFFFF"), ContrastColor.onLightHex)
    }

    func testReadableHex_toleratesLeadingHashAndLowercase() {
        XCTAssertEqual(ContrastColor.readableHex(onBackground: "#2b2b2b"), ContrastColor.onDarkHex)
    }

    func testReadableHex_malformedBackground_fallsBackToOnLight() {
        XCTAssertEqual(ContrastColor.readableHex(onBackground: "nope"), ContrastColor.onLightHex)
    }
}
