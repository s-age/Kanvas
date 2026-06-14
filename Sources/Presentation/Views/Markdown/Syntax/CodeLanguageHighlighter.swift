import Foundation

/// A per-language code-block highlighter: declares the info-string identifiers it answers to and
/// produces `[CodeToken]` for a block of source text.
///
/// **Extensibility contract** — adding a language is one file under `Languages/`: declare
/// `identifiers` (lower-cased fence info strings / aliases) plus the token rules, then register the
/// type in `CodeHighlighterRegistry`. No other site changes.
///
/// `Sendable` and built from pure `Foundation` (`NSRegularExpression`), so the type can be held in
/// the registry across actors and unit-tested without AppKit.
protocol CodeLanguageHighlighter: Sendable {
    /// Lower-cased info-string identifiers this highlighter claims (e.g. `["swift"]`,
    /// `["ts", "tsx", "typescript", "js", "jsx", "javascript"]`).
    static var identifiers: [String] { get }

    /// Returns the coloured tokens for `text`. Ranges are absolute within `text` (the caller offsets
    /// them to the block's content range). `nsRange` is the full `text` range, passed in so the
    /// implementation need not recompute it.
    func tokens(in text: String, range nsRange: NSRange) -> [CodeToken]
}
