import AppKit

/// Fonts and colours for Markdown source-mode highlighting, resolved from the board's
/// `MarkdownSettingsResponse` (base font size, per-level heading sizes, code/quote colours, and
/// the monospaced-body toggle). AppKit-typed because the Markdown editor is the one sanctioned
/// AppKit surface in Presentation — macOS 15's SwiftUI `TextEditor` cannot style text inline
/// (see `.swiftlint.yml` `presentation_no_appkit`).
///
/// A value type (not a static enum) so each editor builds a theme from its board's settings and
/// rebuilds it when they change. `MarkdownTheme.default` covers the brief pre-load window before
/// settings arrive, using the `MarkdownAppearance` defaults.
///
/// `@MainActor`-isolated because `NSFont`/`NSColor` are non-`Sendable`; all access happens on the
/// main actor (the `NSTextView` coordinator), so this satisfies Swift 6 strict concurrency.
@MainActor
struct MarkdownTheme {
    let baseFont: NSFont
    let boldFont: NSFont
    let italicFont: NSFont
    /// Bold-italic font — derived from `boldFont` via the italic trait (for `***x***` syntax).
    let boldItalicFont: NSFont
    /// Inline-code font — always monospaced, one point smaller, regardless of the body toggle.
    let monoFont: NSFont
    /// Editor background — resolved in priority order: Markdown-specific override, then the
    /// board's Global background override, then the system text-editing background when both are
    /// unset. Applied to the `NSTextView` and its scroll view.
    let backgroundColor: NSColor
    let textColor: NSColor
    let markerColor: NSColor
    let accentColor: NSColor
    let codeColor: NSColor
    let quoteColor: NSColor
    /// Link / autolink / image text color. Resolved from `settings.linkColorHex` when set;
    /// falls back to `MarkdownAppearance.linkDefaultHex` (Primer dark approximation).
    let linkColor: NSColor
    /// Full-width background for fenced code blocks (also applied as `.backgroundColor` on
    /// inline-code runs). Resolved from `settings.codeBlockBackgroundColorHex` when set;
    /// falls back to `MarkdownAppearance.codeBlockBackgroundDefaultHex`.
    let codeBlockBackgroundColor: NSColor
    /// Left border bar color for blockquote lines. Resolved from `settings.quoteBorderColorHex`
    /// when set; falls back to `MarkdownAppearance.quoteBorderDefaultHex`.
    let quoteBorderColor: NSColor
    /// Thickness of the blockquote left border bar in points.
    let quoteBorderWidth: CGFloat
    /// Extra hanging-indent added to list continuation lines beyond the measured prefix width.
    let listIndentExtra: CGFloat
    /// `paragraphSpacing` applied to list item lines.
    let listItemSpacing: CGFloat
    /// `lineSpacing` applied to all body lines.
    let lineSpacing: CGFloat
    /// Per-token-kind code-block syntax foreground colours: the built-in GitHub Primer palette with
    /// any `settings.syntaxColorOverrides` layered on top. Resolved once here so the per-token
    /// highlight path (`styleCodeBlockSyntax`) does a dictionary lookup, not a hex parse.
    let syntaxColors: [CodeTokenKind: NSColor]
    /// Full-width diff line-background colours (`diffAdded` / `diffRemoved`), built-in palette with
    /// any override layered on top. Consumed by `MarkdownDecorationPainter`'s diff-line fill.
    let syntaxLineBackgrounds: [CodeTokenKind: NSColor]

    private let headingSizes: [CGFloat]
    private let useMonospaced: Bool

    /// Heading font sized per level (`#` = 1 … `######` = 6); always bold (monospaced when the
    /// body toggle is on).
    func headingFont(level: Int) -> NSFont {
        let idx = min(max(level - 1, 0), headingSizes.count - 1)
        let size = headingSizes[idx]
        return useMonospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: .bold)
            : NSFont.boldSystemFont(ofSize: size)
    }

    init(settings: MarkdownSettingsResponse?, global: GlobalSettingsResponse?) {
        let baseSize = CGFloat(settings?.baseFontSize ?? MarkdownAppearance.defaultBaseFontSize)
        let mono = settings?.useMonospacedFont ?? MarkdownAppearance.defaultUseMonospacedFont
        let body = mono
            ? NSFont.monospacedSystemFont(ofSize: baseSize, weight: .regular)
            : NSFont.systemFont(ofSize: baseSize)

        self.useMonospaced = mono
        self.baseFont = body
        let bold = mono
            ? NSFont.monospacedSystemFont(ofSize: baseSize, weight: .bold)
            : NSFont.boldSystemFont(ofSize: baseSize)
        self.boldFont = bold
        self.italicFont = NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask)
        self.boldItalicFont = NSFontManager.shared.convert(bold, toHaveTrait: .italicFontMask)
        self.monoFont = NSFont.monospacedSystemFont(ofSize: baseSize - 1, weight: .regular)

        let rawHeadings = settings?.headingSizes ?? MarkdownAppearance.defaultHeadingSizes
        let headings = rawHeadings.isEmpty ? MarkdownAppearance.defaultHeadingSizes : rawHeadings
        self.headingSizes = headings.map { CGFloat($0) }

        // Background resolution: Markdown-specific override wins; falls back to the Global
        // override; then the native text-editing background. Text colour mirrors the Kanban board.
        let markdownBgHex = settings?.editorBackgroundColorHex
        let globalBgHex = global?.backgroundColorHex
        self.backgroundColor = markdownBgHex.map { NSColor(hex: $0) }
            ?? globalBgHex.map { NSColor(hex: $0) }
            ?? .textBackgroundColor
        self.textColor = global?.textColorHex.map { NSColor(hex: $0) } ?? .labelColor
        self.markerColor = .tertiaryLabelColor
        self.accentColor = .controlAccentColor
        // Fallback hex matches the Settings picker's "cleared" preview (single source in
        // `MarkdownAppearance`), so clearing an override renders exactly what the picker shows.
        self.codeColor = NSColor(hex: settings?.codeColorHex ?? MarkdownAppearance.codeDefaultHex)
        self.quoteColor = NSColor(hex: settings?.quoteColorHex ?? MarkdownAppearance.quoteDefaultHex)
        self.linkColor = NSColor(hex: settings?.linkColorHex ?? MarkdownAppearance.linkDefaultHex)
        self.codeBlockBackgroundColor = NSColor(
            hex: settings?.codeBlockBackgroundColorHex ?? MarkdownAppearance.codeBlockBackgroundDefaultHex
        )
        self.quoteBorderColor = NSColor(
            hex: settings?.quoteBorderColorHex ?? MarkdownAppearance.quoteBorderDefaultHex
        )
        self.quoteBorderWidth = CGFloat(
            settings?.quoteBorderWidth ?? MarkdownAppearance.defaultQuoteBorderWidth
        )
        self.listIndentExtra = CGFloat(settings?.listIndentExtra ?? 0)
        self.listItemSpacing = CGFloat(settings?.listItemSpacing ?? 0)
        self.lineSpacing = CGFloat(settings?.lineSpacing ?? MarkdownAppearance.defaultLineSpacing)

        // Resolve the syntax-highlight palette: built-in GitHub Primer colours with the per-board
        // settings overrides (token-kind key → hex) layered on top. Empty overrides ⇒ built-in only.
        // Foreground reads the plain `syntaxKey`s; the diff line *backgrounds* read a separate `.bg`
        // key namespace, so the two are configured independently.
        let storedOverrides = settings?.syntaxColorOverrides ?? [:]
        let foreground = CodeTokenKind.resolveOverrides(storedOverrides)
        let lineBackgrounds = CodeTokenKind.resolveLineBackgroundOverrides(storedOverrides)
        self.syntaxColors = GitHubSyntaxPalette.resolvedColors(overrides: foreground)
        self.syntaxLineBackgrounds = GitHubSyntaxPalette.resolvedLineBackgrounds(overrides: lineBackgrounds)
    }

    static let `default` = MarkdownTheme(settings: nil, global: nil)
}
