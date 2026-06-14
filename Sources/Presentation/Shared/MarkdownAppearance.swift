import Foundation

/// Presentation-side constants for the Markdown editor settings tab. The size bounds mirror the
/// Domain `MarkdownSettings` clamp (Presentation cannot import the entity; the entity stays the
/// authoritative clamp on every domain entry). The default *values* are not mirrored — they derive
/// from `MarkdownSettingsResponse.default` (the Domain `MarkdownSettings.default`), so there is one
/// source. The code/quote default hex (nil-override fallbacks with no Domain counterpart) are the
/// single source shared by the `MarkdownTheme` draw-side fallback (used before settings load and on
/// a cleared override) and the Settings → Markdown clearable colour pickers — so a "cleared" picker
/// shows exactly the colour the editor renders.
enum MarkdownAppearance {
    static let minBaseFontSize: Double = 10
    static let maxBaseFontSize: Double = 32
    static let minHeadingSize: Double = 10
    static let maxHeadingSize: Double = 48

    // Defaults are derived from the Domain `MarkdownSettings.default` (via its Response), so the
    // reset-to-defaults target and the editor's draw-side fallback share the single Domain source —
    // no hand-copied literal to drift. (Only the size *bounds* below remain literal mirrors, pinned
    // by `MarkdownAppearanceParityTests`; a single `.default` instance cannot carry clamp bounds.)
    //
    // These are kept as named aliases (rather than inlining `MarkdownSettingsResponse.default.*` at
    // each call site, as the Canvas tab does) because they have a *second* consumer beyond Settings:
    // the `MarkdownTheme` draw-side fallback (`Views/Markdown/MarkdownTheme.swift`), used before
    // settings load / on a cleared override. Canvas has no such draw-side consumer, hence the
    // asymmetry — don't "normalize" one side to match the other.
    static let defaultBaseFontSize = MarkdownSettingsResponse.default.baseFontSize
    static let defaultHeadingSizes = MarkdownSettingsResponse.default.headingSizes
    static let defaultUseMonospacedFont = MarkdownSettingsResponse.default.useMonospacedFont

    /// Fallback hex for inline-code / blockquote colour when no per-board override is set.
    /// Approximates `systemPink` / `systemGray`; fixed so the picker's cleared preview matches the
    /// rendered colour (cleared-override single-source-of-truth convention).
    static let codeDefaultHex = "FF2D55"
    static let quoteDefaultHex = "8E8E93"

    // Block-decoration fallbacks.
    // GitHub Primer dark-mode approximations; cleared picker shows this colour and the editor
    // renders the same shade, keeping the single-source-of-truth convention.

    /// Fallback hex for fenced-code-block full-width background (GitHub Primer dark `#161B22`).
    static let codeBlockBackgroundDefaultHex = "161B22"
    /// Fallback hex for the blockquote left border bar (GitHub Primer dark `#3B434B`).
    static let quoteBorderDefaultHex = "3B434B"
    /// Fallback hex for link / autolink / image text color (GitHub Primer dark `#4493F8`).
    static let linkDefaultHex = "4493F8"

    /// A user-configurable code-block syntax token kind for the Settings → Markdown palette: its
    /// stable persisted key (matches `CodeTokenKind.syntaxKey` in the Markdown carve-out), a display
    /// label, and the light-mode GitHub Primer hex shown as the picker's "cleared" preview (the
    /// built-in colour an absent override inherits). Kept here (Foundation-only) so the SwiftUI
    /// Settings tab — which cannot import the AppKit carve-out's `CodeTokenKind` — drives its pickers
    /// without an AppKit dependency. The keys/labels are a fixed list, pinned by
    /// `MarkdownAppearanceSyntaxParityTests` against the carve-out's `syntaxKey`.
    struct SyntaxTokenDescriptor: Sendable, Equatable, Identifiable {
        let key: String
        let label: String
        /// Light-mode Primer hex (no leading `#`), the picker's cleared-state preview.
        let defaultLightHex: String
        var id: String { key }
    }

    /// The token kinds surfaced in Settings → Markdown, in display order (general kinds first, then
    /// the diff-line foreground kinds). Mirrors the carve-out's `CodeTokenKind.userConfigurableKinds`;
    /// the light-mode hex mirrors `GitHubSyntaxPalette`'s built-in light values. Both parities are
    /// pinned by `MarkdownAppearanceSyntaxParityTests`.
    static let syntaxTokenDescriptors: [SyntaxTokenDescriptor] = [
        SyntaxTokenDescriptor(key: "keyword", label: "Keyword", defaultLightHex: "cf222e"),
        SyntaxTokenDescriptor(key: "type", label: "Type", defaultLightHex: "8250df"),
        SyntaxTokenDescriptor(key: "string", label: "String", defaultLightHex: "0a3069"),
        SyntaxTokenDescriptor(key: "number", label: "Number", defaultLightHex: "0550ae"),
        SyntaxTokenDescriptor(key: "comment", label: "Comment", defaultLightHex: "6e7781"),
        SyntaxTokenDescriptor(key: "function", label: "Function", defaultLightHex: "8250df"),
        SyntaxTokenDescriptor(key: "constant", label: "Constant", defaultLightHex: "0550ae"),
        SyntaxTokenDescriptor(key: "attribute", label: "Attribute", defaultLightHex: "cf222e"),
        SyntaxTokenDescriptor(key: "variable", label: "Variable", defaultLightHex: "953800"),
        // Diff-line foreground colours. The diff line *background* is now configured independently
        // via `lineBackgroundDescriptors` below (a separate `.bg` override-key namespace), so an
        // override here retints only the foreground, never the line background.
        SyntaxTokenDescriptor(key: "diffAdded", label: "Diff Added", defaultLightHex: "1f883d"),
        SyntaxTokenDescriptor(key: "diffRemoved", label: "Diff Removed", defaultLightHex: "cf222e"),
        SyntaxTokenDescriptor(key: "diffHunkHeader", label: "Diff Hunk Header", defaultLightHex: "0550ae"),
        SyntaxTokenDescriptor(key: "diffMeta", label: "Diff Meta", defaultLightHex: "6e7781"),
    ]

    /// A user-configurable diff-line **background** override for the Settings → Markdown palette. Its
    /// stable persisted key is the carve-out's `CodeTokenKind.lineBackgroundKey` (e.g. `diffAdded.bg`)
    /// — a *separate* namespace from `SyntaxTokenDescriptor.key` (the foreground), so the line
    /// background is retinted independently of the foreground. Unlike a foreground token, the built-in
    /// line background is a light/dark **pair** (`GitHubSyntaxPalette.defaultLineBackgroundColors`), so
    /// this descriptor carries both default hexes; the cleared picker previews both built-in swatches
    /// (light + dark — ticket 4AC24F98), while a user override stays appearance-neutral (one hex for
    /// both modes, consistent with every other override). Pinned against the carve-out by
    /// `MarkdownAppearanceParityTests`.
    struct LineBackgroundDescriptor: Sendable, Equatable, Identifiable {
        /// The persisted override key (matches `CodeTokenKind.lineBackgroundKey`).
        let key: String
        let label: String
        /// Light-mode built-in Primer hex (no leading `#`), the picker's cleared-state preview.
        let defaultLightHex: String
        /// Dark-mode built-in Primer hex (no leading `#`). Surfaced in the cleared-state preview
        /// alongside `defaultLightHex` (the built-in line background differs by appearance, so the
        /// cleared picker previews both swatches; ticket 4AC24F98). Also pins the built-in dark
        /// default against the carve-out via `MarkdownAppearanceParityTests`.
        let defaultDarkHex: String
        var id: String { key }
    }

    /// The diff-line backgrounds surfaced in Settings → Markdown, in display order. Keys mirror the
    /// carve-out's `CodeTokenKind.lineBackgroundKey`; the hex pairs mirror
    /// `GitHubSyntaxPalette.defaultLineBackgroundColors`. Both parities are pinned by
    /// `MarkdownAppearanceParityTests`.
    static let lineBackgroundDescriptors: [LineBackgroundDescriptor] = [
        LineBackgroundDescriptor(
            key: "diffAdded.bg", label: "Diff Added Background",
            defaultLightHex: "e6ffec", defaultDarkHex: "033a16"
        ),
        LineBackgroundDescriptor(
            key: "diffRemoved.bg", label: "Diff Removed Background",
            defaultLightHex: "ffebe9", defaultDarkHex: "67060c"
        ),
    ]

    static let defaultQuoteBorderWidth = MarkdownSettingsResponse.default.quoteBorderWidth
    static let minQuoteBorderWidth: Double = 1
    static let maxQuoteBorderWidth: Double = 8

    // Paragraph-styling and background-override constants.
    // Mirror the Domain `MarkdownSettings` clamp bounds — pinned by `MarkdownAppearanceParityTests`.
    static let maxListIndentExtra: Double = 40  // mirrors MarkdownSettings.maxListIndentExtra
    static let maxListItemSpacing: Double = 20  // mirrors MarkdownSettings.maxListItemSpacing
    static let maxLineSpacing: Double = 20      // mirrors MarkdownSettings.maxLineSpacing
    static let defaultLineSpacing = MarkdownSettingsResponse.default.lineSpacing
}
