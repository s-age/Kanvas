import Foundation

/// TypeScript / JavaScript highlighter (also covers JSX/TSX info strings). Rule order: comments and
/// strings first (high priority so a `//` inside a string is not mistaken for a comment, and a
/// keyword inside a string is left alone), then keywords / types / numbers.
struct TypeScriptHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["ts", "tsx", "typescript", "js", "jsx", "javascript"]

    private static let keywords = [
        "abstract", "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "declare", "default", "delete", "do", "else", "enum", "export", "extends",
        "false", "finally", "for", "from", "function", "get", "if", "implements", "import", "in",
        "instanceof", "interface", "is", "keyof", "let", "namespace", "new", "of", "private",
        "protected", "public", "readonly", "return", "set", "static", "super", "switch", "this",
        "throw", "true", "try", "type", "typeof", "var", "void", "while", "yield", "null",
        "undefined", "satisfies",
    ]

    private static let types = [
        "string", "number", "boolean", "any", "unknown", "never", "object", "symbol", "bigint",
        "Array", "Promise", "Record", "Partial", "Readonly", "Map", "Set",
    ]

    private static let rules: [CodeRule] = [
        CodeRule("//[^\\n]*", .comment, highPriority: true),
        CodeRule("/\\*[\\s\\S]*?\\*/", .comment, highPriority: true),
        CodeRule("\"(?:\\\\.|[^\"\\\\\\n])*\"", .string, highPriority: true),
        CodeRule("'(?:\\\\.|[^'\\\\\\n])*'", .string, highPriority: true),
        CodeRule("`(?:\\\\.|[^`\\\\])*`", .string, highPriority: true),
        CodeRule("@[A-Za-z_][A-Za-z0-9_]*", .attribute),
        CodeRule("\\b(?:" + keywords.joined(separator: "|") + ")\\b", .keyword),
        CodeRule("\\b(?:" + types.joined(separator: "|") + ")\\b", .type),
        CodeRule("\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?(?:[eE][+-]?\\d+)?)\\b", .number),
        CodeRule("\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", .function),
    ]

    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken] {
        CodeScanner.scan(text, range: nsRange, rules: Self.rules)
    }
}
