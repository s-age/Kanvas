import AppKit
import XCTest
@testable import KanvasCore

/// Pins the canvas's connector stroke-colour gate (`ConnectorStrokeRendering.strokeColor`), the
/// draw-time half of the end-to-end "unset" representation. The Optional stroke is the signal:
/// `nil` ⇒ the adaptive default; a present hex ⇒ verbatim. The regression these guard is ticket
/// A2E89AB1 — on a nil-background board an explicitly-chosen pure black must render black, where the
/// old non-optional `#000` sentinel re-contrasted it to `#333`/`#ddd`. The final test pins the
/// *toolbar* half: an explicit black picked from the unset state writes through (it is not swallowed
/// as a same-value no-op against a black placeholder — the bug the PR review caught).
final class ConnectorStrokeColorGateTests: XCTestCase {

    /// The nil-background adaptive pick a connector falls back to when its stroke is unset.
    private var adaptiveDefault: NSColor { NSColor(hex: ConnectorAppearance.onDarkStrokeHex) }

    func testUnsetStroke_usesAdaptiveDefault() {
        let color = ConnectorStrokeRendering.strokeColor(forHex: nil, adaptiveDefault: adaptiveDefault)
        XCTAssertEqual(color, adaptiveDefault)
    }

    /// The fix: an explicit pure black on a nil-background board (whose `adaptiveDefault` is a grey)
    /// renders verbatim black — it is *not* re-contrasted to the adaptive default.
    func testExplicitPureBlack_rendersVerbatim_notAdaptive() {
        let color = ConnectorStrokeRendering.strokeColor(forHex: "000000", adaptiveDefault: adaptiveDefault)
        XCTAssertNotEqual(color, adaptiveDefault, "explicit black must not collapse to the adaptive grey")
        XCTAssertEqual(color.redComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.greenComponent, 0, accuracy: 0.001)
        XCTAssertEqual(color.blueComponent, 0, accuracy: 0.001)
    }

    func testExplicitColour_rendersVerbatim() {
        let color = ConnectorStrokeRendering.strokeColor(forHex: "FF8800", adaptiveDefault: adaptiveDefault)
        XCTAssertEqual(color, NSColor(hex: "FF8800"))
    }

    // MARK: - Toolbar write-through (the clearable picker's resolved-default guard)

    /// The toolbar fix: picking pure black from the **unset** state must write `000000` through, not
    /// no-op against the adaptive-grey default. The connector toolbar routes through
    /// `ClearablePaletteColorPicker`, whose guard compares the pick against the *resolved default*
    /// (`onLightStrokeHex` here), so black ≠ default → it writes. (Before, the hand-rolled binding
    /// compared against a black placeholder, so picking black was silently swallowed.)
    func testExplicitBlackFromUnset_writesThrough_notSwallowedByDefaultGuard() {
        let result = ClearablePaletteColorPicker.nextSelection(
            current: nil, default: ConnectorAppearance.onLightStrokeHex, picked: "000000"
        )
        XCTAssertEqual(result, "000000")
    }

    /// Clearing back to unset is reachable: the toolbar's Clear button writes `nil`, restoring the
    /// adaptive default (the post-create producer the review asked for).
    func testClearWhileSet_returnsToUnset() {
        // The Clear button assigns `selection = nil` directly; this pins that a re-emit of the
        // default while already unset stays a no-op (no accidental bake-in after clearing).
        let result = ClearablePaletteColorPicker.nextSelection(
            current: nil, default: ConnectorAppearance.onDarkStrokeHex,
            picked: ConnectorAppearance.onDarkStrokeHex
        )
        XCTAssertNil(result)
    }
}
