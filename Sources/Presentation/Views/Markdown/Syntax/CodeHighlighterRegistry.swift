import Foundation

/// Resolves a fenced-code-block info string (lower-cased) to the highlighter that claims it.
///
/// **Extensibility** — register a new language by appending its highlighter to `allHighlighters`;
/// the alias map is rebuilt from each type's `identifiers`. No other site changes.
///
/// Pure `Foundation`; `@MainActor` only to share the editor's isolation (the lookup itself is
/// stateless). The map is a static constant built once.
enum CodeHighlighterRegistry {
    /// Every registered language highlighter. Add a new `Languages/` type here to wire it in.
    private static let allHighlighters: [any CodeLanguageHighlighter] = [
        TypeScriptHighlighter(),
        SwiftHighlighter(),
        PHPHighlighter(),
        MermaidHighlighter(),
        DiffHighlighter(),
        ShellHighlighter(),
    ]

    /// info-string identifier (lower-cased) → highlighter.
    private static let byIdentifier: [String: any CodeLanguageHighlighter] = {
        var map: [String: any CodeLanguageHighlighter] = [:]
        for highlighter in allHighlighters {
            for identifier in type(of: highlighter).identifiers {
                map[identifier] = highlighter
            }
        }
        return map
    }()

    /// Returns the highlighter for `infoString` (case-insensitive), or `nil` for an empty /
    /// unsupported language — in which case the code block keeps the plain mono + code colour.
    static func highlighter(for infoString: String) -> (any CodeLanguageHighlighter)? {
        let key = infoString.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return byIdentifier[key]
    }
}
