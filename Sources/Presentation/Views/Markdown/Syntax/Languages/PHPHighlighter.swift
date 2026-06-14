import Foundation

/// PHP highlighter. Comments (`//`, `#`, `/* */`) and strings are matched first; then `$variables`,
/// keywords, and numbers. The `$var` rule emits the `.variable` kind (added to the shared vocabulary
/// for PHP and Shell).
struct PHPHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["php"]

    private static let keywords = [
        "abstract", "and", "array", "as", "break", "callable", "case", "catch", "class", "clone",
        "const", "continue", "declare", "default", "do", "echo", "else", "elseif", "empty",
        "enddeclare", "endfor", "endforeach", "endif", "endswitch", "endwhile", "enum", "extends",
        "final", "finally", "fn", "for", "foreach", "function", "global", "goto", "if",
        "implements", "include", "include_once", "instanceof", "insteadof", "interface", "isset",
        "list", "match", "namespace", "new", "or", "print", "private", "protected", "public",
        "readonly", "require", "require_once", "return", "static", "switch", "throw", "trait", "try",
        "unset", "use", "var", "while", "xor", "yield", "true", "false", "null", "self", "parent",
        "string", "int", "float", "bool", "void", "object", "mixed",
    ]

    private static let rules: [CodeRule] = [
        CodeRule("//[^\\n]*", .comment, highPriority: true),
        // A `#` only opens a PHP comment at start-of-line or after whitespace, and never
        // immediately before `[` — `#[...]` is a PHP 8 attribute, not a comment. `(?:^|\s)`
        // consumes the boundary; the `(?!\[)` lookahead leaves attributes for the later rules;
        // group 1 is the comment body. Mirrors the Shell `#` rule (ticket 2CE3A582 r2-1).
        CodeRule("(?:^|\\s)(#(?!\\[)[^\\n]*)", .comment, group: 1, highPriority: true),
        CodeRule("/\\*[\\s\\S]*?\\*/", .comment, highPriority: true),
        CodeRule("\"(?:\\\\.|[^\"\\\\\\n])*\"", .string, highPriority: true),
        CodeRule("'(?:\\\\.|[^'\\\\\\n])*'", .string, highPriority: true),
        CodeRule("\\$[A-Za-z_][A-Za-z0-9_]*", .variable),
        CodeRule("\\b(?:" + keywords.joined(separator: "|") + ")\\b", .keyword),
        CodeRule("\\b(?:0[xX][0-9a-fA-F]+|\\d+(?:\\.\\d+)?)\\b", .number),
        CodeRule("\\b[A-Za-z_][A-Za-z0-9_]*(?=\\s*\\()", .function),
    ]

    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken] {
        CodeScanner.scan(text, range: nsRange, rules: Self.rules)
    }
}
