import XCTest
@testable import KanvasCore

/// The canvas seed presets and default values are now single-sourced: Presentation reads
/// `CanvasSettingsResponse.default` (derived from the Domain `CanvasSettings.default`), so there is
/// no preset-value mirror left to pin. The remaining `StickyAppearance` constants below are *bounds*
/// (preset-size cap / min sizes) — a single `.default` instance cannot carry clamp bounds, so they
/// stay literal mirrors and these tests keep them honest against the authoritative Domain values.
final class CanvasDefaultsParityTests: XCTestCase {

    func testMaxPresetDimensionMirrorsDomain() {
        XCTAssertEqual(StickyAppearance.maxPresetDimension, StickyPreset.maxDimension)
    }

    func testMinPresetBoundsMirrorStickySize() {
        XCTAssertEqual(StickyAppearance.minStickyWidth, StickySize.minWidth)
        XCTAssertEqual(StickyAppearance.minStickyHeight, StickySize.minHeight)
    }

    func testDefaultTextColorMirrorsDomain() {
        XCTAssertEqual(StickyAppearance.defaultTextColorHex, StickyTextStyle.defaultColorHex)
        XCTAssertEqual(CanvasSettings.default.defaultTextColorHex, StickyTextStyle.defaultColorHex)
        // The canvas default text colour Presentation now reads is the Domain-derived Response value.
        XCTAssertEqual(CanvasSettingsResponse.default.defaultTextColorHex, StickyTextStyle.defaultColorHex)
    }
}
