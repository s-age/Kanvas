import Foundation

/// Shell (sh/bash/zsh) highlighter. `#` comments and quoted strings are matched first; then
/// `$VAR` / `${VAR}` expansions (`.variable`), shell keywords, and common builtins.
struct ShellHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["sh", "bash", "zsh", "shell"]

    private static let keywords = [
        "if", "then", "else", "elif", "fi", "for", "while", "until", "do", "done", "case", "esac",
        "function", "in", "select", "return", "break", "continue", "local", "export", "readonly",
        "declare", "typeset", "set", "unset", "shift", "exit", "trap", "source",
    ]

    private static let builtins = [
        "echo", "cd", "ls", "pwd", "cat", "grep", "sed", "awk", "rm", "mkdir", "cp", "mv", "touch",
        "chmod", "chown", "find", "test", "printf", "read", "eval", "exec", "kill", "git", "swift",
    ]

    private static let rules: [CodeRule] = [
        // A `#` only opens a comment at start-of-line or after whitespace — anchoring on
        // group 1 keeps a mid-token `#` (e.g. the `$#` positional-count param, `${#var}`) from
        // being eaten as a comment. `(?:^|\s)` consumes the boundary; group 1 is the comment body.
        CodeRule("(?:^|\\s)(#[^\\n]*)", .comment, group: 1, highPriority: true),
        CodeRule("\"(?:\\\\.|[^\"\\\\])*\"", .string, highPriority: true),
        CodeRule("'[^']*'", .string, highPriority: true),
        CodeRule("\\$\\{[^}]*\\}|\\$[A-Za-z_][A-Za-z0-9_]*|\\$[0-9@*#?$!-]", .variable),
        CodeRule("\\b(?:" + keywords.joined(separator: "|") + ")\\b", .keyword),
        CodeRule("\\b(?:" + builtins.joined(separator: "|") + ")\\b", .function),
        CodeRule("\\b\\d+\\b", .number),
    ]

    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken] {
        CodeScanner.scan(text, range: nsRange, rules: Self.rules)
    }
}
