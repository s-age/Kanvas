import AppKit

/// Bridges the persisted, Presentation-owned syntax-colour override map
/// (`MarkdownSettings.syntaxColorOverrides` → `MarkdownSettingsResponse.syntaxColorOverrides`,
/// a `[String: String]` of token-kind key → hex) into the AppKit `[CodeTokenKind: NSColor]` the
/// `GitHubSyntaxPalette` resolver and `MarkdownTheme` consume.
///
/// The string keys are the storage contract — defined once here as `CodeTokenKind.syntaxKey` so a
/// persisted board keeps decoding even if the `CodeTokenKind` case names change. Lives in the
/// Markdown AppKit carve-out because it produces `NSColor`; the key vocabulary itself is pure.
extension CodeTokenKind {

    /// Stable persisted key for this token kind in `MarkdownSettings.syntaxColorOverrides`. **Never
    /// rename a returned literal** — it is a storage contract shared with persisted boards.
    var syntaxKey: String {
        switch self {
        case .keyword: return "keyword"
        case .type: return "type"
        case .string: return "string"
        case .number: return "number"
        case .comment: return "comment"
        case .function: return "function"
        case .constant: return "constant"
        case .attribute: return "attribute"
        case .variable: return "variable"
        case .diffAdded: return "diffAdded"
        case .diffRemoved: return "diffRemoved"
        case .diffHunkHeader: return "diffHunkHeader"
        case .diffMeta: return "diffMeta"
        }
    }

    /// The token kinds a user may recolour in Settings → Markdown. The diff-line kinds are surfaced
    /// for their **foreground** colour (`diffAdded`/`diffRemoved`, plus the `@@`-line `diffHunkHeader`
    /// drawn bold and `diffMeta`). The diff line-*background* is configured independently via the
    /// separate `lineBackgroundKey` namespace below, so the foreground `syntaxKey` no longer also
    /// retints the line background.
    static let userConfigurableKinds: [CodeTokenKind] = [
        .keyword, .type, .string, .number, .comment, .function, .constant, .attribute, .variable,
        .diffAdded, .diffRemoved, .diffHunkHeader, .diffMeta,
    ]

    /// Stable persisted key for this kind's **line background** override in
    /// `MarkdownSettings.syntaxColorOverrides`, distinct from the foreground `syntaxKey` so the diff
    /// line background can be retinted independently of the foreground. Only the diff line kinds that
    /// actually paint a full-width background (`diffAdded`/`diffRemoved`) have one; every other kind
    /// returns `nil`. **Never rename a returned literal** — it is a storage contract shared with
    /// persisted boards.
    var lineBackgroundKey: String? {
        switch self {
        case .diffAdded: return "diffAdded.bg"
        case .diffRemoved: return "diffRemoved.bg"
        default: return nil
        }
    }

    /// The diff line kinds whose full-width line *background* a user may recolour in
    /// Settings → Markdown — independently of the matching foreground override. Mirrors the kinds
    /// `GitHubSyntaxPalette` paints a built-in line background for.
    static let lineBackgroundConfigurableKinds: [CodeTokenKind] = [.diffAdded, .diffRemoved]

    /// Resolves a persisted override map (token-kind key → hex) into `[CodeTokenKind: NSColor]`,
    /// dropping any key that does not match a known token kind (a forward-compatible read). An
    /// override hex is appearance-neutral (one colour for both light/dark) by design. Reads only the
    /// **foreground** `syntaxKey`s — the `.bg` line-background keys are resolved separately by
    /// `resolveLineBackgroundOverrides(_:)`.
    static func resolveOverrides(_ hexByKey: [String: String]) -> [CodeTokenKind: NSColor] {
        var resolved: [CodeTokenKind: NSColor] = [:]
        for kind in CodeTokenKind.allCases {
            if let hex = hexByKey[kind.syntaxKey] {
                resolved[kind] = NSColor(hex: hex)
            }
        }
        return resolved
    }

    /// Resolves the **line-background** overrides from the same persisted map, reading each diff
    /// kind's `lineBackgroundKey` (e.g. `diffAdded.bg`) rather than its foreground `syntaxKey`. Keeps
    /// the line background independent of the foreground colour. An override hex is appearance-neutral
    /// (one colour for both light/dark) by design.
    static func resolveLineBackgroundOverrides(
        _ hexByKey: [String: String]
    ) -> [CodeTokenKind: NSColor] {
        var resolved: [CodeTokenKind: NSColor] = [:]
        for kind in lineBackgroundConfigurableKinds {
            if let key = kind.lineBackgroundKey, let hex = hexByKey[key] {
                resolved[kind] = NSColor(hex: hex)
            }
        }
        return resolved
    }
}
