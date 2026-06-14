import Foundation

/// Semantic classification of a code-block token, mapped to a foreground colour by
/// `GitHubSyntaxPalette`. Deliberately AppKit-free (pure `Foundation`) so every language
/// highlighter and `CodeScanner` can be unit-tested without a display context.
///
/// The common vocabulary (`keyword … variable`) is shared across languages; the `diff*` cases are
/// line-oriented and only emitted by `DiffHighlighter` — the `diffAdded` / `diffRemoved` kinds also
/// drive the full-width line-background decoration in `MarkdownDecorationPainter`.
enum CodeTokenKind: Equatable, Sendable, CaseIterable {
    case keyword
    case type
    case string
    case number
    case comment
    case function
    case constant
    case attribute
    case variable

    // diff-only kinds
    case diffAdded
    case diffRemoved
    case diffHunkHeader
    case diffMeta
}

/// One coloured token: an `NSRange` (absolute within the code-block content) plus its kind.
/// A value type so highlighters can build `[CodeToken]` arrays with no shared state.
struct CodeToken: Equatable, Sendable {
    let range: NSRange
    let kind: CodeTokenKind
}
