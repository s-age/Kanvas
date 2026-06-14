import Foundation

/// The `kanvas-asset://<assetID>` reference embedded in a card's Markdown body to point at a stored
/// image sidecar asset (`assets/<id>.png`). The string grammar plus the **pure functions** that
/// build, parse, and rewrite it. Shared by the Markdown editor (Presentation — writes/parses it to
/// drive inline image rendering) and the orphan-asset GC (Domain/Services — scans every card's
/// `markdownContent` for it to keep referenced assets reachable).
///
/// Lives in the `Utils` leaf because it is **logic** — regex / string transforms — not bare value
/// declarations (so it does not belong in `Constants`). Presentation cannot import `Domain/Entities`,
/// and Domain cannot import Presentation, so the one place both sharing layers can agree on this
/// behaviour is a dependency-free leaf both see. `Utils` is exactly that: pure functions with no
/// state, no side effects, no I/O, depended on by no other layer. Do not move this onto a Domain
/// entity (Presentation could not then see it).
enum MarkdownImageReference {
    /// URL scheme that distinguishes a kanvas asset reference from any other Markdown image link.
    static let scheme = "kanvas-asset"

    /// The full `scheme://` prefix a reference URL starts with.
    static let urlPrefix = "\(scheme)://"

    // MARK: Shared regex grammar

    /// Regex source for one hex digit — the atom the 8-4-4-4-12 UUID grammar is built from.
    private static let hexDigitPattern = #"[0-9A-Fa-f]"#

    /// Regex source for the bare 8-4-4-4-12 hyphenated hex UUID (no capture group). Shared so the
    /// gallery's reference extraction and the GC's id scan (`referencedAssetIDs`) cannot drift to
    /// two different UUID grammars.
    static var uuidPattern: String {
        "\(hexDigitPattern){8}-\(hexDigitPattern){4}-\(hexDigitPattern){4}-"
            + "\(hexDigitPattern){4}-\(hexDigitPattern){12}"
    }

    /// Regex source for the asset-reference URL `kanvas-asset://<UUID>` with an **optional**
    /// `?w=<points>` display-width query suffix (ticket 4103CA3F). The UUID is **captured** as group
    /// 1; the bare UUID grammar is shared so both reference scanners anchor on one place and cannot
    /// drift. The query suffix is matched but not captured here — `displayWidth(fromURL:)` parses it
    /// off the full URL substring, keeping the scanners' single capture group (the UUID) stable.
    static var referenceURLPattern: String {
        "\(scheme)://(\(uuidPattern))\(widthQuerySuffixPattern)"
    }

    /// Regex source for the optional query suffix on an asset URL. Matches **any** `?…` tail up to the
    /// link's closing delimiter — not just a well-formed `?w=<decimal>` — so a malformed width
    /// (`?w=abc`) still lets the whole reference match and render (degrading to fit-editor-width via
    /// `displayWidth(fromURL:)`, which parses the suffix strictly) instead of falling out of the
    /// scanner and rendering as raw source (finding r1-3). Not a capture group — kept out of the shared
    /// `referenceURLPattern`'s single (UUID) group so the scanners stay one-capture. The actual width
    /// grammar (a bare decimal) is enforced only by the parser, not the matcher.
    private static var widthQuerySuffixPattern: String {
        #"(?:\?[^)\s"]*)?"#
    }

    /// The query-parameter key carrying a per-image display width (in points) on an asset URL:
    /// `kanvas-asset://<id>?w=<points>`. Standard Markdown carries no size, so this query suffix is
    /// the kanvas-native, hand-editable, lossless-round-tripping size grammar (ticket 4103CA3F).
    static let widthQueryKey = "w"

    /// Builds the asset image reference embedded in the body, optionally carrying a per-image display
    /// width: `![](kanvas-asset://<assetID>)` or `![](kanvas-asset://<assetID>?w=<points>)`. The alt
    /// text is intentionally empty — kanvas carries no per-image caption and the renderer keys only
    /// off the asset id. A `nil` (or non-positive) width omits the query, so an unsized reference is
    /// byte-identical to the pre-4103CA3F form (the default "fit editor width" behaviour).
    static func markdown(for assetID: UUID, width: Double? = nil) -> String {
        "![](\(url(for: assetID, width: width)))"
    }

    /// The bare asset URL (no `![]( … )` wrapper), with an optional `?w=<points>` suffix. The width is
    /// emitted with no trailing `.0` for an integral value so a "200pt" reference reads cleanly.
    static func url(for assetID: UUID, width: Double? = nil) -> String {
        let base = "\(urlPrefix)\(assetID.uuidString)"
        guard let width, width > 0 else { return base }
        return "\(base)?\(widthQueryKey)=\(widthQuery(width))"
    }

    /// Renders a positive display width for the `?w=` query suffix: an integral value drops its
    /// trailing `.0` (so "200pt" reads cleanly), a fractional one keeps its decimals. Shared by the
    /// two URL builders so their integer-rounding rule cannot drift.
    private static func widthQuery(_ width: Double) -> String {
        (width.rounded() == width) ? String(Int(width)) : String(width)
    }

    /// Rewrites an existing asset URL's `?w=<points>` width in place, preserving its id (any case) and
    /// any other query content, or clears the width when `width` is `nil`/non-positive. Returns the URL
    /// unchanged when it is not a kanvas asset URL. Used by the resize menu to set a width on the *exact*
    /// reference the user typed without regenerating the surrounding `![alt](… "title")` wrapper (so
    /// alt text and title survive a resize — finding r1-1).
    static func url(byApplyingWidth width: Double?, to assetURL: String) -> String {
        guard assetURL.hasPrefix(urlPrefix) else { return assetURL }
        // Split off any existing query (the `?…` tail) so only the width is rewritten; a foreign query
        // key would be dropped, but kanvas only ever emits `?w=`, so the tail is width-only in practice.
        let base = assetURL.prefix { $0 != "?" }
        guard let width, width > 0 else { return String(base) }
        return "\(base)?\(widthQueryKey)=\(widthQuery(width))"
    }

    /// Parses the asset id out of a single reference URL string (the `kanvas-asset://<id>` inside the
    /// link's parentheses), or `nil` when it is not a kanvas asset URL. Case-insensitive on the UUID
    /// so a lowercased/uppercased id both resolve. Tolerates (and ignores) a `?w=…` width suffix.
    static func assetID(fromURL url: String) -> UUID? {
        guard url.hasPrefix(urlPrefix) else { return nil }
        let body = url.dropFirst(urlPrefix.count)
        let idPart = body.prefix { $0 != "?" }
        return UUID(uuidString: String(idPart))
    }

    /// Parses the per-image display width (in points) out of an asset URL's `?w=<points>` suffix, or
    /// `nil` when the URL is unsized or malformed. Only a positive, finite value is returned — a
    /// zero/negative/non-numeric suffix (`?w=abc`) falls back to `nil` (fit-editor-width), never a
    /// broken size. The scanners' suffix matcher (`widthQuerySuffixPattern`) is deliberately permissive
    /// so such a malformed reference still matches and renders at fit-width here, rather than failing
    /// the match and showing raw `![](…?w=abc)` source (finding r1-3).
    static func displayWidth(fromURL url: String) -> Double? {
        guard url.hasPrefix(urlPrefix), let queryStart = url.firstIndex(of: "?") else { return nil }
        let query = url[url.index(after: queryStart)...]
        let prefix = "\(widthQueryKey)="
        guard query.hasPrefix(prefix),
              let width = Double(query.dropFirst(prefix.count)),
              width.isFinite, width > 0 else { return nil }
        return width
    }

    /// Removes the **first** complete image reference to `assetID` from a Markdown body, returning the
    /// rewritten body — or `nil` when the body holds no reference to that id (the caller treats `nil`
    /// as not-found). Matches the whole `![alt](kanvas-asset://<id>[?w=…][ "title")` construct, not just
    /// the URL, so the leftover `![]( … )` syntax goes too; the id match is case-insensitive (a
    /// hand-edited / MCP-written reference may carry a lowercase id). With duplicate references only the
    /// first is removed (the cell-delete + refcount semantics: drop one reference, keep the rest).
    ///
    /// The add paths (`addMarkdownImage`, the editor drop) insert the reference on its own line as
    /// `\n<ref>\n`, so removing the construct alone would leave a blank line behind. To keep the body
    /// tidy this also consumes one surrounding newline (the trailing one if present, else the leading
    /// one), collapsing the own-line insertion back to nothing without disturbing an inline reference's
    /// surrounding prose.
    static func removingFirstReference(to assetID: UUID, in markdown: String) -> String? {
        guard markdown.contains(urlPrefix) else { return nil }
        // The full `![alt](url[ "title"])` image construct, capturing nothing — the alt text and an
        // optional bare-or-quoted title both vary, so match them permissively up to the closing `)`.
        // The URL is anchored on the shared scheme + UUID grammar (the same `referenceURLPattern` the
        // scanners use), with this id pinned in so only references to *this* asset match.
        let urlPattern = "\(scheme)://\(assetID.uuidString)\(widthQuerySuffixPattern)"
        let imagePattern = #"!\[[^\]]*\]\(\#(urlPattern)(?:\s+"[^"]*")?\)"#
        // `.ignoresCase()` covers the case-insensitive id match (a hand-edited / MCP reference may use
        // a lowercase id). The scheme is already lowercase, and the surrounding `![]( … )` syntax is
        // case-irrelevant, so applying it to the whole pattern is safe.
        guard let regex = try? Regex(imagePattern).ignoresCase(),
              let match = try? regex.firstMatch(in: markdown) else { return nil }
        let lower = match.range.lowerBound
        let upper = match.range.upperBound
        var removalLower = lower
        var removalUpper = upper
        // Collapse the add path's own-line `\n<ref>\n`: consume the trailing newline if there is one,
        // otherwise the leading newline. Consuming exactly one side leaves no blank line and never
        // glues two unrelated lines together.
        if upper < markdown.endIndex, markdown[upper] == "\n" {
            removalUpper = markdown.index(after: upper)
        } else if lower > markdown.startIndex, markdown[markdown.index(before: lower)] == "\n" {
            removalLower = markdown.index(before: lower)
        }
        var result = markdown
        result.removeSubrange(removalLower..<removalUpper)
        return result
    }

    /// Every asset id referenced anywhere in a Markdown body, as a set (duplicates collapse). Matches
    /// `kanvas-asset://<UUID>` regardless of surrounding `![]( … )` syntax so a reference survives
    /// manual edits to the alt text or link title. The hex+hyphen UUID grammar is matched directly;
    /// only well-formed UUIDs are returned, so stray scheme text never yields a phantom id.
    static func referencedAssetIDs(in markdown: String) -> Set<UUID> {
        guard markdown.contains(urlPrefix) else { return [] }
        // Built locally rather than as a static `let`: `Regex` is not `Sendable`, so a shared static
        // is a concurrency error, and this scan runs once per card during the startup GC (not per
        // keystroke), so the construction cost is irrelevant. The scheme + UUID grammar comes from
        // the shared `referenceURLPattern` so it cannot drift from the editor's range-bearing scan.
        // Error handling matches that scan (`try?` + guard) rather than `try!`: the pattern is a
        // compile-time constant so a failure is impossible, but a same-shape guard keeps the two
        // scanners consistent and carries no force-unwrap.
        guard let referenceRegex = try? Regex(referenceURLPattern) else { return [] }
        var ids: Set<UUID> = []
        for match in markdown.matches(of: referenceRegex) {
            // Capture group 1 is the UUID (the only parenthesised group in `referenceURLPattern`).
            guard let group = match.output[1].substring,
                  let assetID = UUID(uuidString: String(group)) else { continue }
            ids.insert(assetID)
        }
        return ids
    }
}
