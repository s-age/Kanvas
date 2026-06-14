import XCTest
@testable import KanvasCore

/// Presentation cannot import `Domain`, so the Global seed colour palette is re-declared as
/// literals in Presentation (`SettingsViewModel.GlobalDefaults.paletteValues`). This test pins that
/// mirror to the authoritative Domain seed (`PaletteColor.defaultPalette`) so a future change to one
/// side that forgets the other fails loudly here — preventing a silent reset-button / seed drift.
@MainActor
final class GlobalDefaultsParityTests: XCTestCase {

    func testPaletteValuesMirrorDomainDefaultPalette() {
        let mirror = SettingsViewModel.GlobalDefaults.paletteValues
        let domain = PaletteColor.defaultPalette

        XCTAssertEqual(mirror.count, domain.count)
        for (m, d) in zip(mirror, domain) {
            XCTAssertEqual(m.colorHex, d.colorHex)
            XCTAssertEqual(m.label, d.label)
        }
    }

    func testMaxPaletteLabelLengthMirrorsDomain() {
        XCTAssertEqual(SettingsViewModel.maxPaletteLabelLength, PaletteColor.maxLabelLength)
    }
}
