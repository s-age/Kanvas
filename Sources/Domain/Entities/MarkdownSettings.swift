struct MarkdownSettings: Sendable, Equatable {
    var baseFontSize: Double
    var headingSizes: [Double]
    var codeColorHex: String?
    var quoteColorHex: String?
    var useMonospacedFont: Bool
    /// Full-width background tint for fenced code blocks (and inline-code glyph-run background).
    /// `nil` → Presentation falls back to its Primer-approximation constant.
    var codeBlockBackgroundColorHex: String?
    /// Left border bar color for blockquote lines.
    /// `nil` → Presentation falls back to its Primer-approximation constant.
    var quoteBorderColorHex: String?
    /// Thickness of the blockquote left border bar in points; clamped to `[minQuoteBorderWidth, maxQuoteBorderWidth]`.
    var quoteBorderWidth: Double
    /// Link/autolink/image text color override.
    /// `nil` → Presentation falls back to its Primer-approximation constant.
    var linkColorHex: String?
    /// Markdown-editor-specific background colour override (hex).
    /// Resolution order in `MarkdownTheme`: this override → Global background override → system
    /// `.textBackgroundColor`. `nil` = inherit from Global/system (no Primer fallback constant).
    var editorBackgroundColorHex: String?
    /// Extra hanging indent added to list item continuation lines on top of the measured prefix
    /// width, in points; clamped to `[0, maxListIndentExtra]`. Default 0 = measure-only.
    var listIndentExtra: Double
    /// Additional `paragraphSpacing` applied to list lines, in points;
    /// clamped to `[0, maxListItemSpacing]`. Default 0 = no extra gap.
    var listItemSpacing: Double
    /// `lineSpacing` applied to every body line, in points;
    /// clamped to `[0, maxLineSpacing]`. Default 2 pt.
    var lineSpacing: Double
    /// Per-token-kind code-block syntax-highlight colour overrides, keyed by a stable token-kind
    /// identifier (the Presentation-owned vocabulary in `CodeTokenKind.syntaxKey`; the Settings UI
    /// surfaces these via `MarkdownAppearance.syntaxTokenDescriptors`). A
    /// present entry overrides the built-in GitHub Primer palette colour for that token kind; an
    /// absent key inherits the built-in colour. Empty (the default) = entirely built-in palette.
    /// The Domain stores this opaquely — the key vocabulary and the AppKit colour resolution stay in
    /// the Presentation Markdown carve-out, so this entity carries no UI dependency.
    var syntaxColorOverrides: [String: String]

    static let minBaseFontSize: Double = 10
    static let maxBaseFontSize: Double = 32
    /// Markdown supports headings H1–H6, so `headingSizes` is always exactly this many elements —
    /// `init` pads short arrays / trims long ones so every consumer (the editor's per-level font
    /// lookup, the settings UI's per-level steppers) can index `0..<headingLevels` safely.
    static let headingLevels = 6
    static let defaultHeadingSizes: [Double] = [25, 22, 19, 17, 16, 15]
    static let minQuoteBorderWidth: Double = 1
    static let maxQuoteBorderWidth: Double = 8
    static let defaultQuoteBorderWidth: Double = 3
    static let maxListIndentExtra: Double = 40
    static let maxListItemSpacing: Double = 20
    static let maxLineSpacing: Double = 20
    static let defaultLineSpacing: Double = 2

    init(
        baseFontSize: Double = 14,
        headingSizes: [Double] = MarkdownSettings.defaultHeadingSizes,
        codeColorHex: String? = nil,
        quoteColorHex: String? = nil,
        useMonospacedFont: Bool = false,
        codeBlockBackgroundColorHex: String? = nil,
        quoteBorderColorHex: String? = nil,
        quoteBorderWidth: Double = MarkdownSettings.defaultQuoteBorderWidth,
        linkColorHex: String? = nil,
        editorBackgroundColorHex: String? = nil,
        listIndentExtra: Double = 0,
        listItemSpacing: Double = 0,
        lineSpacing: Double = MarkdownSettings.defaultLineSpacing,
        syntaxColorOverrides: [String: String] = [:]
    ) {
        self.baseFontSize = min(max(baseFontSize, MarkdownSettings.minBaseFontSize), MarkdownSettings.maxBaseFontSize)
        self.headingSizes = MarkdownSettings.normalizedHeadingSizes(headingSizes)
        self.codeColorHex = codeColorHex
        self.quoteColorHex = quoteColorHex
        self.useMonospacedFont = useMonospacedFont
        self.codeBlockBackgroundColorHex = codeBlockBackgroundColorHex
        self.quoteBorderColorHex = quoteBorderColorHex
        self.quoteBorderWidth = min(max(quoteBorderWidth,
                                       MarkdownSettings.minQuoteBorderWidth),
                                    MarkdownSettings.maxQuoteBorderWidth)
        self.linkColorHex = linkColorHex
        self.editorBackgroundColorHex = editorBackgroundColorHex
        self.listIndentExtra = min(max(listIndentExtra, 0), MarkdownSettings.maxListIndentExtra)
        self.listItemSpacing = min(max(listItemSpacing, 0), MarkdownSettings.maxListItemSpacing)
        self.lineSpacing = min(max(lineSpacing, 0), MarkdownSettings.maxLineSpacing)
        self.syntaxColorOverrides = syntaxColorOverrides
    }

    /// Forces `headingSizes` to exactly `headingLevels` entries: an empty array becomes the full
    /// default; a short array is padded from the default for the missing levels; a long array is
    /// trimmed. Keeps the "exactly H1–H6" invariant regardless of a malformed persisted value.
    private static func normalizedHeadingSizes(_ sizes: [Double]) -> [Double] {
        guard !sizes.isEmpty else { return defaultHeadingSizes }
        guard sizes.count != headingLevels else { return sizes }
        return (0..<headingLevels).map { idx in
            idx < sizes.count ? sizes[idx] : defaultHeadingSizes[idx]
        }
    }

    static let `default` = MarkdownSettings()
}
