import XCTest
@testable import KanvasCore

/// Pins the `ClearablePaletteColorPicker` resolved-default guard: while a colour is "unset"
/// (`selection == nil`, meaning "use system default"), a re-emitted value equal to the default must
/// NOT bake the default in as an explicit colour. SwiftUI's `ColorPicker` re-emits its bound value
/// on redraw, so without this guard a redraw would silently turn a defaulted element into an
/// explicitly-coloured one (and mark the settings form dirty).
final class PaletteColorPickerGuardTests: XCTestCase {

    func testReEmittedDefaultWhileNil_staysNil() {
        // selection == nil, the well re-emits the default colour → must skip the write.
        let result = ClearablePaletteColorPicker.nextSelection(
            current: nil, default: "FF9500", picked: "FF9500"
        )
        XCTAssertNil(result)
    }

    func testReEmittedDefaultWhileNil_caseInsensitive() {
        let result = ClearablePaletteColorPicker.nextSelection(
            current: nil, default: "ff9500", picked: "FF9500"
        )
        XCTAssertNil(result)
    }

    func testPickingANonDefaultColourWhileNil_writesIt() {
        // An actual user pick that differs from the default must go through.
        let result = ClearablePaletteColorPicker.nextSelection(
            current: nil, default: "FF9500", picked: "007AFF"
        )
        XCTAssertEqual(result, "007AFF")
    }

    func testReEmittedCurrentWhileSet_staysNoOp() {
        // selection is an explicit colour; re-emitting the same hex is a no-op.
        let result = ClearablePaletteColorPicker.nextSelection(
            current: "007AFF", default: "FF9500", picked: "007AFF"
        )
        XCTAssertNil(result)
    }

    func testChangingAnExplicitColour_writes() {
        let result = ClearablePaletteColorPicker.nextSelection(
            current: "007AFF", default: "FF9500", picked: "34C759"
        )
        XCTAssertEqual(result, "34C759")
    }

    func testPickingTheDefaultExplicitlyWhileSet_writesIt() {
        // While a non-default colour is set, deliberately picking the default colour is a real
        // change and must be written (it only no-ops when the resolved current already equals it).
        let result = ClearablePaletteColorPicker.nextSelection(
            current: "007AFF", default: "FF9500", picked: "FF9500"
        )
        XCTAssertEqual(result, "FF9500")
    }
}
