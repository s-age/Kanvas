import Foundation

/// Shared upper bounds for caller-supplied free text and binary payloads. The Request layer is the
/// validation boundary, and the JSON store persists the **whole board as one blob** — so an
/// unbounded payload bloats that blob and, on the next save, is re-read and re-broadcast: every
/// `mutate` reloads the whole file inside the cross-process lock, and `BoardStoreWatcher` reloads
/// the open app on each change. A model that hands `markdown_set` / `board_card_*` /
/// `canvas_sticky_*` (or a future image tool) a runaway string or asset is therefore rejected here,
/// not silently persisted.
///
/// Scope: this guards **persistence**, not the transient in-memory spike — the payload is already
/// fully decoded by JSON deserialization before `validate()` runs, so the check is CPU + disk
/// defense, not an ingest-time memory cap. And unlike `NumericBoundsValidation` (whose entity
/// initializers re-clamp numeric fields on untrusted-JSON load), length has **no** load-side
/// re-validation: a store already containing an oversized title/markdown loads unbounded, because
/// truncating on load would silently lose data. The cap lives only on the write path, by design.
///
/// Each length check counts at most `max + 1` Swift `Character`s (`prefix`-bounded) so the guard
/// against a pathological string does not itself walk the entire attacker-controlled payload; the
/// image limit counts raw bytes.
enum ContentSizeValidation {
    /// Max characters for any title (card / board / column).
    static let maxTitleLength = 1_000
    /// Max characters for a card's Markdown detail.
    static let maxMarkdownLength = 1_000_000
    /// Max characters for a sticky's text.
    static let maxStickyContentLength = 100_000
    /// Max characters for a card's assignee.
    static let maxAssigneeLength = 1_000
    /// Max characters for a card's linked PR URL.
    static let maxURLLength = 2_048
    /// Max bytes for an image's encoded payload.
    static let maxImageByteCount = 32 * 1024 * 1024

    static func validate(title: String) throws {
        guard isWithin(title, maxTitleLength) else {
            throw ValidationError.titleTooLong(max: maxTitleLength)
        }
    }

    static func validate(markdown: String) throws {
        guard isWithin(markdown, maxMarkdownLength) else {
            throw ValidationError.contentTooLong(max: maxMarkdownLength)
        }
    }

    static func validate(stickyContent: String) throws {
        guard isWithin(stickyContent, maxStickyContentLength) else {
            throw ValidationError.contentTooLong(max: maxStickyContentLength)
        }
    }

    static func validate(assignee: String) throws {
        guard isWithin(assignee, maxAssigneeLength) else {
            throw ValidationError.contentTooLong(max: maxAssigneeLength)
        }
    }

    static func validate(url: String) throws {
        guard isWithin(url, maxURLLength) else {
            throw ValidationError.contentTooLong(max: maxURLLength)
        }
    }

    static func validate(imageByteCount: Int) throws {
        guard imageByteCount <= maxImageByteCount else {
            throw ValidationError.imageDataTooLarge(maxBytes: maxImageByteCount)
        }
    }

    /// Bounded length check: stops after `max + 1` characters, so a gigabyte-long string is rejected
    /// without grapheme-breaking the whole payload it is meant to guard against.
    private static func isWithin(_ value: String, _ max: Int) -> Bool {
        value.prefix(max + 1).count <= max
    }
}
