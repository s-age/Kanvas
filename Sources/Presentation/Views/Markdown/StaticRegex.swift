import Foundation

/// Compiles a compile-time-constant regex pattern that is known to be valid, trapping if it is not.
///
/// Every caller passes a string literal that ships in the binary, so a compile failure can only mean
/// a developer typo in that literal — a programmer error that must surface loudly at first use, not a
/// runtime input condition to recover from. Centralising the single `try!` here (covered by
/// `StaticRegexTests`) lets the syntax-highlighting patterns drop their per-site
/// `swiftlint:disable:this force_try` annotations: there is exactly one audited force-try in the
/// Markdown highlighting code, instead of one per pattern.
///
/// Pure `Foundation` so both the AppKit-side `MarkdownHighlighter` and the AppKit-free `CodeScanner`
/// share it without pulling AppKit into the latter.
///
/// - Parameters:
///   - pattern: A compile-time-constant pattern literal.
///   - options: Matching options; defaults to none. Multi-line patterns pass `[.anchorsMatchLines]`.
/// - Returns: The compiled `NSRegularExpression`.
enum StaticRegex {
    static func compile(
        _ pattern: String, options: NSRegularExpression.Options = []
    ) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Invalid static regex pattern \(pattern.debugDescription): \(error)")
        }
    }
}
