import XCTest
@testable import KanvasCore

/// `MarkdownSettings.init` enforces two invariants on untrusted persisted input: `baseFontSize`
/// clamps into `[min, max]`, `headingSizes` is always exactly `headingLevels` (H1–H6) entries
/// so every consumer can index `0..<headingLevels` safely, and `quoteBorderWidth` clamps into
/// `[minQuoteBorderWidth, maxQuoteBorderWidth]`.
final class MarkdownSettingsTests: XCTestCase {

    // MARK: - baseFontSize clamp

    func testInit_baseFontSizeBelowMinimum_clampsUp() {
        let settings = MarkdownSettings(baseFontSize: 2)
        XCTAssertEqual(settings.baseFontSize, MarkdownSettings.minBaseFontSize)
    }

    func testInit_baseFontSizeAboveMaximum_clampsDown() {
        let settings = MarkdownSettings(baseFontSize: 999)
        XCTAssertEqual(settings.baseFontSize, MarkdownSettings.maxBaseFontSize)
    }

    // MARK: - headingSizes normalization

    func testInit_emptyHeadingSizes_fallsBackToDefault() {
        let settings = MarkdownSettings(headingSizes: [])
        XCTAssertEqual(settings.headingSizes, MarkdownSettings.defaultHeadingSizes)
    }

    func testInit_shortHeadingSizes_padsFromDefault() {
        let settings = MarkdownSettings(headingSizes: [40, 38])
        XCTAssertEqual(
            settings.headingSizes,
            [40, 38] + MarkdownSettings.defaultHeadingSizes[2...]
        )
    }

    func testInit_longHeadingSizes_trimsToHeadingLevels() {
        let settings = MarkdownSettings(headingSizes: [40, 38, 36, 34, 32, 30, 28, 26])
        XCTAssertEqual(settings.headingSizes, [40, 38, 36, 34, 32, 30])
    }

    func testInit_exactHeadingSizes_preservedVerbatim() {
        let exact: [Double] = [30, 28, 26, 24, 22, 20]
        let settings = MarkdownSettings(headingSizes: exact)
        XCTAssertEqual(settings.headingSizes, exact)
    }

    func testInit_normalizedHeadingSizes_alwaysHasHeadingLevelsCount() {
        for sizes in [[], [10.0], Array(repeating: 12.0, count: 9)] {
            XCTAssertEqual(MarkdownSettings(headingSizes: sizes).headingSizes.count, MarkdownSettings.headingLevels)
        }
    }

    // MARK: - quoteBorderWidth clamp

    func testInit_quoteBorderWidthBelowMinimum_clampsUp() {
        let settings = MarkdownSettings(quoteBorderWidth: 0)
        XCTAssertEqual(settings.quoteBorderWidth, MarkdownSettings.minQuoteBorderWidth)
    }

    func testInit_quoteBorderWidthAboveMaximum_clampsDown() {
        let settings = MarkdownSettings(quoteBorderWidth: 99)
        XCTAssertEqual(settings.quoteBorderWidth, MarkdownSettings.maxQuoteBorderWidth)
    }

    func testInit_quoteBorderWidthAtMinimum_preservedVerbatim() {
        let settings = MarkdownSettings(quoteBorderWidth: MarkdownSettings.minQuoteBorderWidth)
        XCTAssertEqual(settings.quoteBorderWidth, MarkdownSettings.minQuoteBorderWidth)
    }

    func testInit_quoteBorderWidthAtMaximum_preservedVerbatim() {
        let settings = MarkdownSettings(quoteBorderWidth: MarkdownSettings.maxQuoteBorderWidth)
        XCTAssertEqual(settings.quoteBorderWidth, MarkdownSettings.maxQuoteBorderWidth)
    }

    func testInit_quoteBorderWidthDefault_equalsDefaultConstant() {
        let settings = MarkdownSettings()
        XCTAssertEqual(settings.quoteBorderWidth, MarkdownSettings.defaultQuoteBorderWidth)
    }

    // MARK: - nil-able color fields pass through unchanged

    func testInit_codeBlockBackgroundColorHex_nilByDefault() {
        XCTAssertNil(MarkdownSettings().codeBlockBackgroundColorHex)
    }

    func testInit_quoteBorderColorHex_nilByDefault() {
        XCTAssertNil(MarkdownSettings().quoteBorderColorHex)
    }

    func testInit_linkColorHex_nilByDefault() {
        XCTAssertNil(MarkdownSettings().linkColorHex)
    }

    func testInit_colorHexValues_preservedVerbatim() {
        let settings = MarkdownSettings(
            codeBlockBackgroundColorHex: "161B22",
            quoteBorderColorHex: "3B434B",
            linkColorHex: "4493F8"
        )
        XCTAssertEqual(settings.codeBlockBackgroundColorHex, "161B22")
        XCTAssertEqual(settings.quoteBorderColorHex, "3B434B")
        XCTAssertEqual(settings.linkColorHex, "4493F8")
    }

    // MARK: - editorBackgroundColorHex

    func testInit_editorBackgroundColorHex_nilByDefault() {
        XCTAssertNil(MarkdownSettings().editorBackgroundColorHex)
    }

    func testInit_editorBackgroundColorHex_preservedVerbatim() {
        let settings = MarkdownSettings(editorBackgroundColorHex: "0D1117")
        XCTAssertEqual(settings.editorBackgroundColorHex, "0D1117")
    }

    // MARK: - listIndentExtra clamp

    func testInit_listIndentExtraBelowZero_clampsUp() {
        let settings = MarkdownSettings(listIndentExtra: -5)
        XCTAssertEqual(settings.listIndentExtra, 0)
    }

    func testInit_listIndentExtraAboveMax_clampsDown() {
        let settings = MarkdownSettings(listIndentExtra: 999)
        XCTAssertEqual(settings.listIndentExtra, MarkdownSettings.maxListIndentExtra)
    }

    func testInit_listIndentExtraAtZero_preservedVerbatim() {
        XCTAssertEqual(MarkdownSettings(listIndentExtra: 0).listIndentExtra, 0)
    }

    func testInit_listIndentExtraAtMax_preservedVerbatim() {
        XCTAssertEqual(MarkdownSettings(listIndentExtra: MarkdownSettings.maxListIndentExtra).listIndentExtra,
                       MarkdownSettings.maxListIndentExtra)
    }

    // MARK: - listItemSpacing clamp

    func testInit_listItemSpacingBelowZero_clampsUp() {
        let settings = MarkdownSettings(listItemSpacing: -1)
        XCTAssertEqual(settings.listItemSpacing, 0)
    }

    func testInit_listItemSpacingAboveMax_clampsDown() {
        let settings = MarkdownSettings(listItemSpacing: 999)
        XCTAssertEqual(settings.listItemSpacing, MarkdownSettings.maxListItemSpacing)
    }

    func testInit_listItemSpacingDefault_isZero() {
        XCTAssertEqual(MarkdownSettings().listItemSpacing, 0)
    }

    // MARK: - lineSpacing clamp

    func testInit_lineSpacingBelowZero_clampsUp() {
        let settings = MarkdownSettings(lineSpacing: -3)
        XCTAssertEqual(settings.lineSpacing, 0)
    }

    func testInit_lineSpacingAboveMax_clampsDown() {
        let settings = MarkdownSettings(lineSpacing: 999)
        XCTAssertEqual(settings.lineSpacing, MarkdownSettings.maxLineSpacing)
    }

    func testInit_lineSpacingDefault_equalsDefaultConstant() {
        XCTAssertEqual(MarkdownSettings().lineSpacing, MarkdownSettings.defaultLineSpacing)
    }
}
