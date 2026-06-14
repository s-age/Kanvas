import Foundation

/// A single regex-based tokenisation rule: a compiled pattern, the token kind it produces, and the
/// capture-group index to colour (group 0 = whole match). `priority` rules run first and their
/// matched ranges become "consumed" so lower-priority rules (keywords, numbers) never recolour
/// inside a comment or string.
struct CodeRule: Sendable {
    let regex: NSRegularExpression
    let kind: CodeTokenKind
    /// Capture group to emit as the token range. 0 = the whole match.
    let group: Int
    /// `true` for comment/string rules that must mask the regions they cover from later rules.
    let isHighPriority: Bool

    init(_ pattern: String, _ kind: CodeTokenKind, group: Int = 0, highPriority: Bool = false) {
        self.regex = StaticRegex.compile(pattern, options: [.anchorsMatchLines])
        self.kind = kind
        self.group = group
        self.isHighPriority = highPriority
    }
}

/// Shared, language-agnostic scanner used by every keyword/string/comment-based highlighter.
///
/// Two-phase so comments and strings win over keywords:
/// 1. **High-priority pass** — comment/string rules are matched first; their ranges are emitted as
///    tokens *and* recorded as consumed regions.
/// 2. **Remaining pass** — keyword/number/type/etc rules run, but any match overlapping a consumed
///    region is dropped (reusing `MarkdownHighlighter.intersects(_:with:)` so a keyword inside a
///    string literal or comment is never coloured). Within this pass the rules are **first-wins**:
///    a match overlapping a range an *earlier* phase-2 rule already emitted is dropped too, so the
///    rule order in each highlighter is its priority order. This stops the shared `function` rule
///    (`\b\w+(?=\s*\()`, listed last) from also colouring control keywords like `if (` / `for (` —
///    the keyword rule, listed first, claims the range — and lets a `.variable` rule (e.g. shell
///    `$set`) win over a later keyword rule.
///
/// Pure `Foundation` — unit-tested without AppKit. `enum` with a static method (no state).
enum CodeScanner {
    /// Runs `rules` over `text` and returns the resulting tokens, ordered by location.
    /// High-priority (comment/string) rules are applied first and mask their ranges from the rest.
    static func scan(_ text: String, range nsRange: NSRange, rules: [CodeRule]) -> [CodeToken] {
        var tokens: [CodeToken] = []
        var consumed: [NSRange] = []

        // Phase 1 — high-priority comment/string rules, masking their ranges from later rules.
        for rule in rules where rule.isHighPriority {
            rule.regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let match else { return }
                let range = match.range(at: rule.group)
                guard range.location != NSNotFound, range.length > 0 else { return }
                // A comment/string inside an already-consumed comment/string is ignored.
                guard !intersects(range, with: consumed) else { return }
                tokens.append(CodeToken(range: range, kind: rule.kind))
                consumed.append(range)
            }
        }

        // Phase 2 — keyword/number/type rules, first-wins: drop anything inside a consumed
        // (comment/string) region or overlapping a range an earlier phase-2 rule already emitted.
        var emitted: [NSRange] = []
        for rule in rules where !rule.isHighPriority {
            // Ranges this rule emits join `emitted` only after the rule completes, so two
            // non-overlapping matches of the *same* rule never suppress each other.
            var ruleRanges: [NSRange] = []
            rule.regex.enumerateMatches(in: text, range: nsRange) { match, _, _ in
                guard let match else { return }
                let range = match.range(at: rule.group)
                guard range.location != NSNotFound, range.length > 0 else { return }
                guard !intersects(range, with: consumed), !intersects(range, with: emitted) else {
                    return
                }
                tokens.append(CodeToken(range: range, kind: rule.kind))
                ruleRanges.append(range)
            }
            emitted.append(contentsOf: ruleRanges)
        }

        return tokens.sorted { $0.range.location < $1.range.location }
    }

    /// `true` when `range` overlaps any range in `excluded`. A nonisolated copy of
    /// `MarkdownHighlighter.intersects` so the scanner stays pure (AppKit/main-actor free) and
    /// unit-testable without a display context.
    private static func intersects(_ range: NSRange, with excluded: [NSRange]) -> Bool {
        for ex in excluded where range.location < NSMaxRange(ex) && NSMaxRange(range) > ex.location {
            return true
        }
        return false
    }
}
