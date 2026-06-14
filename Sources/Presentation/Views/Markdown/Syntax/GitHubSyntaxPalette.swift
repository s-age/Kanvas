import AppKit

/// GitHub Primer-derived colour palette for code-block syntax highlighting. Each token kind maps to
/// a light/dark hex pair, resolved at draw time by `NSColor(name:dynamicProvider:)` so the colour
/// tracks the editor's effective appearance (no manual light/dark branch at the call site).
///
/// The diff line-background colours are exposed separately — they fill the full line width via
/// `MarkdownDecorationPainter`, not as a text foreground.
///
/// The GitHub Primer hex values live here so the built-in palette is a single tuning point. A
/// per-board **settings override** (`MarkdownSettings.syntaxColorOverrides`, keyed by
/// `CodeTokenKind.syntaxKey`) is layered on top of this default by
/// `resolvedColors(overrides:)` / `resolvedLineBackgrounds(overrides:)`: a present key replaces the
/// built-in colour for that kind, an absent key inherits it. The resolved maps are cached on
/// `MarkdownTheme` (rebuilt only when settings change), so the per-keystroke / per-draw call sites
/// look up an `NSColor` rather than re-parsing hex. `@MainActor` to match the rest of the editor and
/// `NSColor` access.
@MainActor
enum GitHubSyntaxPalette {

    /// `true` when the kind should be drawn bold (currently only the diff hunk header `@@`).
    static func isBold(_ kind: CodeTokenKind) -> Bool {
        kind == .diffHunkHeader
    }

    // MARK: - Resolved tables (built-in defaults ← settings overrides)

    /// The foreground colour per token kind, with each `overrides[kind]` hex (a settings override)
    /// replacing the built-in GitHub Primer colour for that kind. An override hex resolves to one
    /// fixed colour for both appearances (a user-chosen colour is appearance-neutral); an absent
    /// override keeps the appearance-tracking built-in dynamic colour.
    ///
    /// Built once per `MarkdownTheme` (settings rarely change relative to keystrokes), so the
    /// per-token draw path does a dictionary lookup, not a hex parse.
    static func resolvedColors(overrides: [CodeTokenKind: NSColor]) -> [CodeTokenKind: NSColor] {
        var resolved = defaultForegroundColors
        for (kind, color) in overrides { resolved[kind] = color }
        return resolved
    }

    /// The full-width line-background colour for each diff line kind that has one, with any
    /// `overrides[kind]` replacing the built-in colour. Only `diffAdded` / `diffRemoved` have a line
    /// background; an override for any other kind is ignored here. The `overrides` here come from the
    /// dedicated `.bg` line-background key namespace (`CodeTokenKind.resolveLineBackgroundOverrides`),
    /// independent of the foreground `resolvedColors(overrides:)` — so retinting the foreground no
    /// longer also retints the line background. The built-in default is a light/dark pair; a present
    /// override hex is appearance-neutral (one colour for both).
    static func resolvedLineBackgrounds(
        overrides: [CodeTokenKind: NSColor]
    ) -> [CodeTokenKind: NSColor] {
        var resolved = defaultLineBackgroundColors
        for (kind, color) in overrides where resolved[kind] != nil {
            resolved[kind] = color
        }
        return resolved
    }

    // MARK: - Cached dynamic built-in tables (built once)

    /// One cached dynamic foreground `NSColor` per token kind. Built once at first access; each
    /// dynamic colour resolves light/dark per the drawing appearance, so a single cached instance
    /// serves both appearances.
    private static let defaultForegroundColors: [CodeTokenKind: NSColor] = Dictionary(
        uniqueKeysWithValues: CodeTokenKind.allCases.map { kind in
            let pair = foregroundHex(for: kind)
            return (kind, dynamic("kanvas.syntax.\(kind)", light: pair.light, dark: pair.dark))
        }
    )

    /// One cached dynamic line-background `NSColor` for each diff line kind that has one.
    private static let defaultLineBackgroundColors: [CodeTokenKind: NSColor] = [
        .diffAdded: dynamic("kanvas.syntax.bg.diffAdded", light: "e6ffec", dark: "033a16"),
        .diffRemoved: dynamic("kanvas.syntax.bg.diffRemoved", light: "ffebe9", dark: "67060c"),
    ]

    // MARK: - Hex tables (GitHub Primer)

    private static func foregroundHex(for kind: CodeTokenKind) -> (light: String, dark: String) {
        switch kind {
        case .keyword, .attribute:
            return ("cf222e", "ff7b72")
        case .type, .function:
            return ("8250df", "d2a8ff")
        case .string:
            return ("0a3069", "a5d6ff")
        case .number, .constant:
            return ("0550ae", "79c0ff")
        case .variable:
            return ("953800", "ffa657")
        case .comment:
            return ("6e7781", "8b949e")
        case .diffAdded:
            return ("1f883d", "3fb950")
        case .diffRemoved:
            return ("cf222e", "f85149")
        case .diffHunkHeader:
            return ("0550ae", "79c0ff")
        case .diffMeta:
            return ("6e7781", "8b949e")
        }
    }

    // MARK: - Appearance resolution

    /// Builds a named dynamic `NSColor` that resolves `light`/`dark` hex per the drawing appearance.
    private static func dynamic(_ name: String, light: String, dark: String) -> NSColor {
        let lightColor = NSColor(hex: light)
        let darkColor = NSColor(hex: dark)
        return NSColor(name: NSColor.Name(name)) { appearance in
            let match = appearance.bestMatch(from: [.aqua, .darkAqua])
            return match == .darkAqua ? darkColor : lightColor
        }
    }
}
