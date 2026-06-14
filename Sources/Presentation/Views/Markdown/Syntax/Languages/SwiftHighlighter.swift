import Foundation

/// Swift highlighter. Comments (`//`, `/* */`) and string literals (including multi-line `"""`) are
/// matched first; then keywords, attributes (`@escaping`), known types, and numbers.
struct SwiftHighlighter: CodeLanguageHighlighter {
    static let identifiers = ["swift"]

    private static let keywords = [
        "associatedtype", "async", "await", "break", "case", "catch", "class", "continue",
        "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false",
        "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "indirect", "init",
        "inout", "internal", "is", "lazy", "let", "mutating", "nil", "nonmutating", "open",
        "operator", "override", "private", "protocol", "public", "repeat", "rethrows", "return",
        "self", "Self", "static", "struct", "subscript", "super", "switch", "throw", "throws",
        "true", "try", "typealias", "unowned", "var", "weak", "where", "while", "some", "any",
        "actor", "nonisolated", "convenience", "required",
    ]

    private static let types = [
        "Int", "UInt", "Double", "Float", "Bool", "String", "Character", "Array", "Dictionary",
        "Set", "Optional", "Result", "Void", "Data", "Date", "URL", "CGFloat", "CGRect",
        "NSRange", "NSString",
    ]

    private static let rules: [CodeRule] = [
        CodeRule("//[^\\n]*", .comment, highPriority: true),
        CodeRule("/\\*[\\s\\S]*?\\*/", .comment, highPriority: true),
        CodeRule("\"\"\"[\\s\\S]*?\"\"\"", .string, highPriority: true),
        CodeRule("\"(?:\\\\.|[^\"\\\\\\n])*\"", .string, highPriority: true),
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
