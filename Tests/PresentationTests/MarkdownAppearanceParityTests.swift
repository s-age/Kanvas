import XCTest
import AppKit
@testable import KanvasCore

/// `MarkdownAppearance` (Presentation) still hand-mirrors the Domain `MarkdownSettings` clamp
/// *bounds* because a single `.default` instance cannot carry bounds and Presentation cannot import
/// `Domain/Entities`. These assertions fail the build if either side drifts. The *default values*
/// (base font size, heading sizes, monospaced toggle, quote-border width, line spacing) are no
/// longer mirrored — `MarkdownAppearance.default*` derive from `MarkdownSettingsResponse.default`
/// (itself the Domain `MarkdownSettings.default`), so there is one source and nothing to pin.
/// (Presentation-only display constants — `min/maxHeadingSize`, `code/quoteDefaultHex` — have no
/// Domain counterpart and are intentionally not asserted here.)
///
/// If you add a new mirrored *bounds* pair (Domain `MarkdownSettings` + Presentation
/// `MarkdownAppearance`) add a matching assertion to this test.
final class MarkdownAppearanceParityTests: XCTestCase {

    func testBaseFontSizeBounds_matchDomainClamp() {
        XCTAssertEqual(MarkdownAppearance.minBaseFontSize, MarkdownSettings.minBaseFontSize)
        XCTAssertEqual(MarkdownAppearance.maxBaseFontSize, MarkdownSettings.maxBaseFontSize)
    }

    // MARK: - Block-decoration and paragraph-styling bounds mirrors (Finding #9)

    func testQuoteBorderWidthBounds_matchDomainClamp() {
        XCTAssertEqual(MarkdownAppearance.minQuoteBorderWidth, MarkdownSettings.minQuoteBorderWidth,
                       "MarkdownAppearance.minQuoteBorderWidth must mirror MarkdownSettings")
        XCTAssertEqual(MarkdownAppearance.maxQuoteBorderWidth, MarkdownSettings.maxQuoteBorderWidth,
                       "MarkdownAppearance.maxQuoteBorderWidth must mirror MarkdownSettings")
    }

    func testMaxListIndentExtra_matchesDomainClamp() {
        XCTAssertEqual(MarkdownAppearance.maxListIndentExtra, MarkdownSettings.maxListIndentExtra,
                       "MarkdownAppearance.maxListIndentExtra must mirror MarkdownSettings")
    }

    func testMaxListItemSpacing_matchesDomainClamp() {
        XCTAssertEqual(MarkdownAppearance.maxListItemSpacing, MarkdownSettings.maxListItemSpacing,
                       "MarkdownAppearance.maxListItemSpacing must mirror MarkdownSettings")
    }

    func testMaxLineSpacing_matchesDomainClamp() {
        XCTAssertEqual(MarkdownAppearance.maxLineSpacing, MarkdownSettings.maxLineSpacing,
                       "MarkdownAppearance.maxLineSpacing must mirror MarkdownSettings")
    }

    // MARK: - Syntax-token descriptor parity (Settings UI ↔ carve-out vocabulary)

    /// The Settings tab's `SyntaxTokenDescriptor` keys must match the carve-out `CodeTokenKind`'s
    /// stable persisted `syntaxKey` for every user-configurable kind — otherwise a picker would
    /// write a key the editor never reads.
    @MainActor
    func testSyntaxTokenDescriptorKeys_matchCarveOutSyntaxKeys() {
        let descriptorKeys = MarkdownAppearance.syntaxTokenDescriptors.map(\.key)
        let kindKeys = CodeTokenKind.userConfigurableKinds.map(\.syntaxKey)
        XCTAssertEqual(descriptorKeys, kindKeys,
                       "Settings syntax-token descriptor keys must mirror CodeTokenKind.syntaxKey")
    }

    /// Each descriptor's `defaultLightHex` (the picker's cleared preview) must equal the built-in
    /// light-mode colour the editor renders when no override is set — the cleared-preview ==
    /// rendered-colour single-source convention.
    @MainActor
    func testSyntaxTokenDescriptorDefaults_matchBuiltInLightPalette() {
        let resolved = GitHubSyntaxPalette.resolvedColors(overrides: [:])
        for descriptor in MarkdownAppearance.syntaxTokenDescriptors {
            guard let kind = CodeTokenKind.userConfigurableKinds.first(
                where: { $0.syntaxKey == descriptor.key }
            ) else {
                XCTFail("No CodeTokenKind for descriptor key \(descriptor.key)")
                continue
            }
            XCTAssertEqual(resolved[kind]?.hex(in: .aqua), descriptor.defaultLightHex,
                           "Cleared preview for \(descriptor.key) must match the built-in light colour")
        }
    }

    // MARK: - Diff line-background descriptor parity (independent override-key namespace)

    /// The Settings tab's `LineBackgroundDescriptor` keys must match the carve-out's
    /// `CodeTokenKind.lineBackgroundKey` for every line-background-configurable kind — otherwise a
    /// picker would write a `.bg` key the editor never reads.
    @MainActor
    func testLineBackgroundDescriptorKeys_matchCarveOutLineBackgroundKeys() {
        let descriptorKeys = MarkdownAppearance.lineBackgroundDescriptors.map(\.key)
        let kindKeys = CodeTokenKind.lineBackgroundConfigurableKinds.compactMap(\.lineBackgroundKey)
        XCTAssertEqual(descriptorKeys, kindKeys,
                       "Line-background descriptor keys must mirror CodeTokenKind.lineBackgroundKey")
    }

    /// The line-background key namespace must be disjoint from the foreground `syntaxKey` namespace,
    /// so an override of one never affects the other.
    @MainActor
    func testLineBackgroundKeys_disjointFromForegroundSyntaxKeys() {
        let backgroundKeys = Set(CodeTokenKind.lineBackgroundConfigurableKinds.compactMap(\.lineBackgroundKey))
        let foregroundKeys = Set(CodeTokenKind.userConfigurableKinds.map(\.syntaxKey))
        XCTAssertTrue(backgroundKeys.isDisjoint(with: foregroundKeys),
                      "Diff line-background keys must not collide with foreground syntax keys")
    }

    /// Each line-background descriptor's light/dark default hex must equal the built-in line
    /// background the editor paints when no override is set — the cleared-preview == rendered-colour
    /// single-source convention, here for both appearances.
    @MainActor
    func testLineBackgroundDescriptorDefaults_matchBuiltInPalette() {
        let resolved = GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: [:])
        for descriptor in MarkdownAppearance.lineBackgroundDescriptors {
            guard let kind = CodeTokenKind.lineBackgroundConfigurableKinds.first(
                where: { $0.lineBackgroundKey == descriptor.key }
            ) else {
                XCTFail("No CodeTokenKind for line-background descriptor key \(descriptor.key)")
                continue
            }
            XCTAssertEqual(resolved[kind]?.hex(in: .aqua), descriptor.defaultLightHex,
                           "Cleared light preview for \(descriptor.key) must match the built-in light bg")
            XCTAssertEqual(resolved[kind]?.hex(in: .darkAqua), descriptor.defaultDarkHex,
                           "Cleared dark preview for \(descriptor.key) must match the built-in dark bg")
        }
    }

    /// A foreground override (plain `diffAdded`) must NOT retint the line background, and a `.bg`
    /// override must NOT retint the foreground — the independence the ticket required.
    @MainActor
    func testForegroundAndLineBackgroundOverrides_areIndependent() {
        let store = ["diffAdded": "112233", "diffAdded.bg": "445566"]
        let foreground = GitHubSyntaxPalette.resolvedColors(
            overrides: CodeTokenKind.resolveOverrides(store)
        )
        let backgrounds = GitHubSyntaxPalette.resolvedLineBackgrounds(
            overrides: CodeTokenKind.resolveLineBackgroundOverrides(store)
        )
        XCTAssertEqual(foreground[.diffAdded]?.hex(in: .aqua), "112233",
                       "Foreground must honour the plain diffAdded override")
        XCTAssertEqual(backgrounds[.diffAdded]?.hex(in: .aqua), "445566",
                       "Line background must honour the diffAdded.bg override, not the foreground key")
    }

    /// Backward compatibility: an existing board that only set the plain `diffAdded` foreground
    /// override must keep the built-in line background (no longer dragged to the foreground hex).
    @MainActor
    func testLegacyForegroundOverride_leavesLineBackgroundAtBuiltIn() {
        let store = ["diffAdded": "112233"]
        let backgrounds = GitHubSyntaxPalette.resolvedLineBackgrounds(
            overrides: CodeTokenKind.resolveLineBackgroundOverrides(store)
        )
        let builtIn = GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: [:])
        XCTAssertEqual(backgrounds[.diffAdded]?.hex(in: .aqua),
                       builtIn[.diffAdded]?.hex(in: .aqua),
                       "A legacy foreground-only override must leave the line background at the built-in")
    }
}
