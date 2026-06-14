import XCTest
import AppKit
@testable import KanvasCore

/// Shared helpers for the split code-block syntax-highlighting test suite under
/// `Tests/PresentationTests/CodeSyntaxHighlight/`. The original single-file suite
/// (`CodeSyntaxHighlightTests`) exceeded the 300-line split threshold (test-unit.md), so it is
/// split per concern: per-language tokeniser tests, the shared `CodeScanner` masking / first-wins
/// tests, and the registry / `fencedCodeBlocks` / painter / palette tests. These free helpers keep
/// each split file self-contained without duplicating the boilerplate.

/// The full `NSRange` of `text`.
func fullRange(_ text: String) -> NSRange {
    NSRange(location: 0, length: (text as NSString).length)
}

/// Returns the substring covered by `token` in `text`.
func substring(_ text: String, _ token: CodeToken) -> String {
    (text as NSString).substring(with: token.range)
}

/// The kinds present at the substring `needle` in `text` after tokenising with `highlighter`.
func kinds(
    of needle: String, in text: String, _ highlighter: any CodeLanguageHighlighter
) -> [CodeTokenKind] {
    let target = (text as NSString).range(of: needle)
    return highlighter.tokens(in: text, range: fullRange(text))
        .filter { NSIntersectionRange($0.range, target).length > 0 }
        .map(\.kind)
}

// MARK: - Test-only hex readback

extension NSColor {
    /// Resolves a (possibly dynamic) colour under `appearanceName` and renders it to a 6-digit
    /// lower-case sRGB hex string for assertion against the palette. Uses
    /// `performAsCurrentDrawingAppearance` so the dynamic provider resolves the right light/dark
    /// variant (macOS has no `resolvedColor(for:)`).
    func hex(in appearanceName: NSAppearance.Name) -> String {
        var result = ""
        let appearance = NSAppearance(named: appearanceName)!
        appearance.performAsCurrentDrawingAppearance {
            guard let rgb = self.usingColorSpace(.sRGB) else { return }
            let r = Int((rgb.redComponent * 255).rounded())
            let g = Int((rgb.greenComponent * 255).rounded())
            let b = Int((rgb.blueComponent * 255).rounded())
            result = String(format: "%02x%02x%02x", r, g, b)
        }
        return result
    }
}
