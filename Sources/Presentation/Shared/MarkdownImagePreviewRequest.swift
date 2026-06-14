import Foundation

/// The "open the image preview window" request, handed from the Markdown gallery to the
/// reusable preview window scene through shared `@Observable` state on `BoardViewModel`
/// (ticket 8511D150). A SwiftUI `Window(id:)` scene cannot receive an `openWindow` payload the
/// way a `WindowGroup(for:)` can, and an `Image`/`NSImage` is not transferable anyway — so the
/// gallery publishes this small value bag and the window re-loads the asset bytes itself via the
/// existing `loadImageData(assetID:)` path (no new I/O, no AppKit type crossing the boundary).
///
/// **Payload shape is the full ordered asset set + the current index, not a lone id** — so the
/// Lightbox navigation (前後画像へのシームレス移動, ticket B23D376B) steps `currentIndex` over `assetIDs`
/// (via `BoardViewModel.stepMarkdownImagePreview(by:)`, gated by `hasPrevious`/`hasNext`) with zero
/// rework: ← / → and the edge `<` / `>` buttons just move the index, and the preview window re-loads
/// `assetIDs[currentIndex]`.
///
/// `boardWindowSize` is the board (board/Kanban) window's size captured *at open time*, in the
/// Markdown AppKit carve-out. It is the initial-size budget: the window opens at the largest rect
/// that preserves the image's aspect ratio while fitting inside `boardWindowSize * 0.8`. It is an
/// initial cap only — the user may freely resize past it afterwards.
struct MarkdownImagePreviewRequest: Equatable, Sendable {
    /// Every asset id the gallery currently shows, in display order. Only `assetIDs[currentIndex]`
    /// is shown now; the full set is carried for the future Lightbox (ticket B23D376B).
    let assetIDs: [UUID]
    /// Index into `assetIDs` of the asset to preview. Always a valid index when non-empty.
    let currentIndex: Int
    /// The board window's size at the moment the preview was opened — the initial-size budget
    /// (80% of this, aspect-preserved). Zero-sized when the board window frame was unavailable,
    /// in which case the window falls back to its minimum size.
    let boardWindowSize: CGSize
    /// A monotonically increasing open token stamped by `BoardViewModel` on every open, so two
    /// *otherwise identical* opens (same asset, same index, same unmoved board window) are still
    /// distinct values. This is what lets the preview window's `onDisappear` identity gate tell an
    /// in-flight teardown apart from a same-thumbnail reopen that arrived during the dismiss
    /// animation: without it, re-opening the very same image with the board window untouched would
    /// be byte-identical to what the teardown owned, and the stale teardown would wipe the reopened
    /// window blank (the empty-window race r1/r2/r3 chase). It carries no display meaning.
    let generation: UInt64

    /// The asset to show now (`assetIDs[currentIndex]`), or `nil` if the index is out of range.
    var currentAssetID: UUID? {
        guard assetIDs.indices.contains(currentIndex) else { return nil }
        return assetIDs[currentIndex]
    }

    /// True when a previous asset exists to step back to — gates the `<` / ← affordance (Lightbox
    /// navigation, ticket B23D376B). False at the first asset (no looping) and for a single-asset
    /// set, so the navigation UI never appears with nowhere to go.
    var hasPrevious: Bool { assetIDs.indices.contains(currentIndex - 1) }

    /// True when a next asset exists to step forward to — gates the `>` / → affordance. False at the
    /// last asset (no looping) and for a single-asset set.
    var hasNext: Bool { assetIDs.indices.contains(currentIndex + 1) }
}
