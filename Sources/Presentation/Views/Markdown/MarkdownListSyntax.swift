import AppKit

/// Shared line-level parsing for Markdown list editing (continuation, indent) and
/// renumbering. The regex captures: 1 = indent, 2 = marker, 3 = ordinal digits (absent
/// for bullets), 4 = spacing, 5 = content.
@MainActor
enum MarkdownListSyntax {
    static let pattern = try! NSRegularExpression(
        pattern: "^([ \\t]*)([-*+]|(\\d+)\\.)([ \\t]+)(.*)$"
    )

    static func match(_ line: NSString) -> NSTextCheckingResult? {
        pattern.firstMatch(in: line as String, range: NSRange(location: 0, length: line.length))
    }

    /// Count of leading spaces/tabs — the item's nesting width.
    static func leadingWhitespace(_ line: NSString) -> Int {
        var count = 0
        while count < line.length {
            let char = line.substring(with: NSRange(location: count, length: 1))
            guard char == " " || char == "\t" else { break }
            count += 1
        }
        return count
    }

    /// The range of the line containing `caret`, excluding its trailing newline.
    static func contentRange(_ ns: NSString, caret: Int) -> NSRange {
        trimmedRange(ns, ns.lineRange(for: NSRange(location: caret, length: 0)))
    }

    /// Strips a trailing newline from a full line range.
    static func trimmedRange(_ ns: NSString, _ fullRange: NSRange) -> NSRange {
        var range = fullRange
        if range.length > 0,
           ns.substring(with: NSRange(location: range.location + range.length - 1, length: 1)) == "\n" {
            range.length -= 1
        }
        return range
    }
}
