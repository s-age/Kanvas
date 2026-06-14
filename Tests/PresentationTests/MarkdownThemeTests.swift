import XCTest
@testable import KanvasCore

/// Tests for `MarkdownTheme` block-decoration color resolution (Primer-approximation fallbacks and
/// explicit overrides) and background resolution order (Markdown override > Global >
/// system `.textBackgroundColor`).
///
/// `@MainActor`-isolated because `MarkdownTheme` (and `NSColor`) are `@MainActor`.
@MainActor
final class MarkdownThemeTests: XCTestCase {

    // MARK: - Fallback (nil settings)

    func testLinkColor_nilSettings_fallsBackToPrimerConstant() {
        let theme = MarkdownTheme(settings: nil, global: nil)

        XCTAssertEqual(theme.linkColor, NSColor(hex: MarkdownAppearance.linkDefaultHex))
    }

    func testCodeBlockBackgroundColor_nilSettings_fallsBackToPrimerConstant() {
        let theme = MarkdownTheme(settings: nil, global: nil)

        XCTAssertEqual(theme.codeBlockBackgroundColor,
                       NSColor(hex: MarkdownAppearance.codeBlockBackgroundDefaultHex))
    }

    func testQuoteBorderColor_nilSettings_fallsBackToPrimerConstant() {
        let theme = MarkdownTheme(settings: nil, global: nil)

        XCTAssertEqual(theme.quoteBorderColor,
                       NSColor(hex: MarkdownAppearance.quoteBorderDefaultHex))
    }

    func testQuoteBorderWidth_nilSettings_fallsBackToDefaultConstant() {
        let theme = MarkdownTheme(settings: nil, global: nil)

        XCTAssertEqual(theme.quoteBorderWidth, CGFloat(MarkdownAppearance.defaultQuoteBorderWidth))
    }

    // MARK: - Explicit overrides win over fallbacks

    func testLinkColor_settingsWithHex_usesOverride() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: "FF0000",
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.linkColor, NSColor(hex: "FF0000"))
    }

    func testCodeBlockBackgroundColor_settingsWithHex_usesOverride() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: "001122", quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.codeBlockBackgroundColor, NSColor(hex: "001122"))
    }

    func testQuoteBorderColor_settingsWithHex_usesOverride() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: "AABBCC",
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.quoteBorderColor, NSColor(hex: "AABBCC"))
    }

    func testQuoteBorderWidth_settingsWithValue_usesOverride() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 6, linkColorHex: nil,
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.quoteBorderWidth, 6)
    }

    // MARK: - Nil color hex fields use fallback (not the override path)

    func testLinkColor_nilLinkColorHex_fallsBackToPrimerConstant() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: nil, listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.linkColor, NSColor(hex: MarkdownAppearance.linkDefaultHex))
    }

    // MARK: - Background resolution order

    func testBackgroundColor_bothNil_fallsBackToSystem() {
        let theme = MarkdownTheme(settings: nil, global: nil)

        XCTAssertEqual(theme.backgroundColor, .textBackgroundColor,
                       "nil markdown + nil global must fall back to system textBackgroundColor")
    }

    func testBackgroundColor_onlyGlobalSet_usesGlobal() {
        let global = GlobalSettingsResponse(
            backgroundColorHex: "112233", textColorHex: nil, colorPalette: []
        )
        let theme = MarkdownTheme(settings: nil, global: global)

        XCTAssertEqual(theme.backgroundColor, NSColor(hex: "112233"),
                       "nil markdown setting must fall back to Global override")
    }

    func testBackgroundColor_markdownOverride_winsOverGlobal() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: "0D1117",
            listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let global = GlobalSettingsResponse(
            backgroundColorHex: "112233", textColorHex: nil, colorPalette: []
        )
        let theme = MarkdownTheme(settings: settings, global: global)

        XCTAssertEqual(theme.backgroundColor, NSColor(hex: "0D1117"),
                       "Markdown-specific override must beat Global override")
    }

    func testBackgroundColor_markdownOverrideWithNilGlobal_usesMarkdown() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: "AABBCC",
            listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.backgroundColor, NSColor(hex: "AABBCC"))
    }

    func testBackgroundColor_nilMarkdownOverrideWithNilGlobal_usesSystem() {
        let settings = MarkdownSettingsResponse(
            baseFontSize: 14,
            headingSizes: MarkdownAppearance.defaultHeadingSizes,
            codeColorHex: nil, quoteColorHex: nil, useMonospacedFont: false,
            codeBlockBackgroundColorHex: nil, quoteBorderColorHex: nil,
            quoteBorderWidth: 3, linkColorHex: nil,
            editorBackgroundColorHex: nil,
            listIndentExtra: 0, listItemSpacing: 0,
            lineSpacing: MarkdownAppearance.defaultLineSpacing, syntaxColorOverrides: [:]
        )
        let theme = MarkdownTheme(settings: settings, global: nil)

        XCTAssertEqual(theme.backgroundColor, .textBackgroundColor)
    }

    // MARK: - Paragraph properties on theme

    func testLineSpacing_defaultSettings_equalsDefaultConstant() {
        let theme = MarkdownTheme(settings: nil, global: nil)
        XCTAssertEqual(theme.lineSpacing, CGFloat(MarkdownAppearance.defaultLineSpacing))
    }

    func testListIndentExtra_nilSettings_isZero() {
        let theme = MarkdownTheme(settings: nil, global: nil)
        XCTAssertEqual(theme.listIndentExtra, 0)
    }

    func testListItemSpacing_nilSettings_isZero() {
        let theme = MarkdownTheme(settings: nil, global: nil)
        XCTAssertEqual(theme.listItemSpacing, 0)
    }
}
