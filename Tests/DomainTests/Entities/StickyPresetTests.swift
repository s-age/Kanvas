import XCTest
@testable import KanvasCore

/// `StickyPreset` enforces two domain rules in its initializer: the label is truncated to at most
/// 3 characters, and the size is clamped to `StickySize`'s bounds. These pin that a hand-edited /
/// out-of-range persisted value is re-normalised on load (every entry routes through `init`).
final class StickyPresetTests: XCTestCase {

    func testInit_truncatesLabelToThreeCharacters() {
        let preset = StickyPreset(label: "TOOLONG", colorHex: "FFFFFF", width: 200, height: 150)

        XCTAssertEqual(preset.label, "TOO")
    }

    func testInit_keepsShortLabelVerbatim() {
        let preset = StickyPreset(label: "S", colorHex: "FFFFFF", width: 200, height: 150)

        XCTAssertEqual(preset.label, "S")
    }

    func testInit_clampsWidthAndHeightToPresetBounds() {
        let tooSmall = StickyPreset(label: "x", colorHex: "FFFFFF", width: 1, height: 1)
        XCTAssertEqual(tooSmall.width, StickySize.minWidth)
        XCTAssertEqual(tooSmall.height, StickySize.minHeight)

        // The preset cap (512) is tighter than `StickySize.max…` (2000).
        let tooBig = StickyPreset(label: "x", colorHex: "FFFFFF", width: 99_999, height: 99_999)
        XCTAssertEqual(tooBig.width, StickyPreset.maxDimension)
        XCTAssertEqual(tooBig.height, StickyPreset.maxDimension)
    }

    func testDefaultPresets_areSML() {
        XCTAssertEqual(StickyPreset.defaultPresets.map(\.label), ["S", "M", "L"])
    }

    func testCanvasSettingsDefault_seedsTheDefaultPresets() {
        XCTAssertEqual(CanvasSettings.default.stickyPresets, StickyPreset.defaultPresets)
    }
}
