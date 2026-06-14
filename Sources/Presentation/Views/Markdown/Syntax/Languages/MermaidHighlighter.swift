import Foundation

/// Mermaid highlighter — token colouring only (no diagram rendering). `%%` comments first, then
/// diagram-type / structural keywords, quoted node labels, arrow operators (as `.keyword`), and
/// numbers.
struct MermaidHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["mermaid", "mmd"]

    private static let keywords = [
        "graph", "flowchart", "sequenceDiagram", "classDiagram", "stateDiagram", "stateDiagram-v2",
        "erDiagram", "gantt", "pie", "journey", "gitGraph", "subgraph", "end", "participant",
        "actor", "loop", "alt", "opt", "par", "note", "class", "state", "section", "title", "TB",
        "TD", "BT", "RL", "LR", "activate", "deactivate", "click", "style", "linkStyle",
    ]

    private static let rules: [CodeRule] = [
        CodeRule("%%[^\\n]*", .comment, highPriority: true),
        CodeRule("\"[^\"\\n]*\"", .string, highPriority: true),
        CodeRule("\\b(?:" + keywords.joined(separator: "|") + ")\\b", .keyword),
        CodeRule("-{1,3}>|={1,3}>|--[xo]|\\.\\.>|-\\.->|:::", .keyword),
        CodeRule("\\b\\d+(?:\\.\\d+)?\\b", .number),
    ]

    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken] {
        CodeScanner.scan(text, range: nsRange, rules: Self.rules)
    }
}
