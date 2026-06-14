import AppKit
import SwiftUI

/// Crash-free replacement for the editor's old inline `NSTextAttachment` image rendering (ticket
/// 04568CD4). Instead of drawing a card's `kanvas-asset://<id>` images *inside* the `NSTextView` —
/// which drove a TextKit-1 layout-hole crash (`-[NSLayoutManager _fillLayoutHoleAtIndex:]` during
/// `NSTextView.sizeToFit`) — the references render as plain styled text in the editor and the images
/// are shown here, in a horizontal fixed-height strip below the notes. No `NSTextView`/TextKit
/// involvement in the image display path, so the layout-hole crash cannot occur.
///
/// Lives in the `Views/Markdown/` AppKit carve-out only so it can decode PNG bytes (`NSImage(data:)`)
/// into a SwiftUI `Image`; the loaded `NSImage` never crosses a ViewModel/DI boundary (the loader
/// hands over `Data`).
struct MarkdownImageGallery: View {
    /// Asset ids referenced by the card body, in first-appearance order (deduplicated).
    let assetIDs: [UUID]
    /// Loads an asset's PNG bytes — `BoardViewModel.loadImageData`, with its three-way outcome.
    let loadImageData: (UUID) async -> CanvasImageLoad
    /// Reports a terminal load failure (missing / undecodable / persistently unreadable) so the
    /// degradation is observable — mirrors the canvas, satisfying "silent failures are forbidden".
    /// `BoardViewModel.reportImageLoadFailure`.
    let reportImageLoadFailure: (UUID, ImageLoadFailureReason) -> Void
    /// Removes the asset's first body reference (and reclaims its bytes when no board references it
    /// any more) — `MarkdownEditorView`'s delete closure, which re-seeds the editor from the rewritten
    /// body. The single domain-owned removal: the gallery never edits the draft itself.
    let deleteImage: (UUID) -> Void

    /// Publishes the preview target onto shared state (`BoardViewModel.markdownImagePreview`) so the
    /// reusable preview window can re-load it — `MarkdownEditorView` wires this to
    /// `BoardViewModel.openMarkdownImagePreview`. The gallery supplies the ordered asset set, the
    /// tapped index, and the board window's current size (read here in the AppKit carve-out, the only
    /// zone that may reach the board window's frame); the VM stamps the monotonic open generation.
    /// Replaces the old `.sheet` modal — the window can be moved and resized, and re-opening a
    /// thumbnail re-targets it.
    let setPreview: (_ assetIDs: [UUID], _ currentIndex: Int, _ boardWindowSize: CGSize) -> Void

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if !assetIDs.isEmpty {
            // Fixed-height horizontal strip (ticket 46653F19): a single row of 100pt-tall
            // thumbnails that scrolls horizontally as the count grows, so the gallery never
            // expands vertically and crowds out the Markdown editor. The old "Images" heading is
            // gone — the strip is thumbnails only.
            ScrollView(.horizontal) {
                LazyHStack(spacing: 12) {
                    ForEach(Array(assetIDs.enumerated()), id: \.element) { index, assetID in
                        MarkdownGalleryCell(assetID: assetID,
                                            loadImageData: loadImageData,
                                            reportImageLoadFailure: reportImageLoadFailure,
                                            // The window re-loads the asset itself; the tap only
                                            // needs to say *which* thumbnail (its index).
                                            onOpen: { openPreview(at: index) },
                                            onDelete: { deleteImage(assetID) })
                    }
                }
                .padding(.vertical, Self.stripVerticalPadding)
            }
            // Pin the strip to exactly its content height (ticket 46653F19). A horizontal
            // ScrollView is greedy on the cross (vertical) axis: with no explicit height it
            // expands to fill the offered space, competing with the editor's
            // `.frame(maxHeight: .infinity)` (MarkdownEditorView) and splitting the right pane
            // ~50/50 — which left a tall dead band between the notes and the thumbnails. Fixing
            // the height to thumbnail + padding lets the editor reclaim all the remaining space.
            .frame(height: MarkdownGalleryCell.thumbnailHeight + Self.stripVerticalPadding * 2)
        }
    }

    /// Vertical padding above and below the thumbnail row, counted into the strip's fixed height
    /// so the editor (greedy `.frame(maxHeight: .infinity)`) reclaims every other point.
    private static let stripVerticalPadding: CGFloat = 4

    /// Publishes the ordered asset set + tapped index + the board window's current size (the
    /// initial-size budget — captured here in the AppKit carve-out) and opens the single reusable
    /// preview window. The payload is the *full* `assetIDs` + index, not a lone id, so the follow-up
    /// Lightbox navigation (ticket B23D376B) can step the index with zero rework.
    private func openPreview(at index: Int) {
        setPreview(assetIDs, index, MarkdownPreviewWindowSizing.boardWindowContentSize())
        openWindow(id: WindowID.markdownImagePreview)
    }
}

/// One gallery thumbnail: lazily loads its asset's bytes and draws them, or shows a placeholder while
/// loading / when the asset is permanently unavailable. `task(id:)` reloads if the cell is reused for
/// a different asset.
private struct MarkdownGalleryCell: View {
    let assetID: UUID
    let loadImageData: (UUID) async -> CanvasImageLoad
    let reportImageLoadFailure: (UUID, ImageLoadFailureReason) -> Void
    /// Called when the (loaded) thumbnail is tapped — the parent opens the reusable preview window
    /// for this asset. The window re-loads the bytes itself, so the tap carries no image. Only
    /// invokable once `phase == .loaded` (the tap target only exists then).
    let onOpen: () -> Void
    /// Removes this asset's first body reference — the hover delete button's action. Wired to
    /// `MarkdownEditorView`'s domain-owned removal, never an inline draft edit.
    let onDelete: () -> Void

    /// Hover state for the delete affordance — the button overlays only while the pointer is over the
    /// cell, so the thumbnail stays uncluttered (mirrors the canvas's hover-revealed handles).
    @State private var isHovering = false

    /// The cell's display state as a single value, so the illegal "loaded *and* failed" pair is
    /// unrepresentable (project convention: make the bad state unrepresentable). The preview window
    /// re-loads the bytes itself, so the loaded case only needs the thumbnail `Image`.
    private enum Phase {
        case loading
        case loaded(Image)
        case failed

        var isLoading: Bool {
            if case .loading = self { return true }
            return false
        }
    }

    /// Retry cap before a recurring *transient* fault is treated as terminal — mirrors the canvas's
    /// `transientImageLoadRetryLimit` so the editor and canvas agree on the same asset store.
    private static let transientRetryLimit = 3

    @State private var phase: Phase = .loading

    /// Fixed thumbnail height (ticket 46653F19) — every cell in the horizontal strip is this tall.
    /// File-internal (not `private`) so the enclosing `MarkdownImageGallery` sizes the strip to the
    /// same constant — one source of truth for the gallery's height.
    static let thumbnailHeight: CGFloat = 100

    var body: some View {
        ZStack {
            switch phase {
            case .loaded(let image):
                // Tappable when loaded: opens the original in the preview window. `scaledToFit`
                // keeps the image's aspect ratio at the fixed 100pt height, so the cell's width
                // varies with the source — no trimming.
                Button { onOpen() } label: {
                    image
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View original image")
                .accessibilityHint("Opens the full-size image")
            case .failed:
                Image(systemName: "photo.badge.exclamationmark")
                    .imageScale(.large)
                    .foregroundStyle(.secondary)
                    // Placeholder has no intrinsic image size, so default to a 100×100 square.
                    .frame(width: Self.thumbnailHeight, height: Self.thumbnailHeight)
            case .loading:
                ProgressView()
                    // Placeholder has no intrinsic image size, so default to a 100×100 square.
                    .frame(width: Self.thumbnailHeight, height: Self.thumbnailHeight)
            }
        }
        .frame(height: Self.thumbnailHeight)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) { deleteButton }
        .onHover { isHovering = $0 }
        .task(id: assetID) { await load() }
        .accessibilityLabel("Referenced image")
    }

    /// Hover-revealed delete affordance: removes the reference (and the asset's bytes when nothing else
    /// references it). Shown for a loaded *or* failed cell — a broken reference is exactly what a user
    /// most wants to remove — but not while loading (the outcome, and thus the asset id's validity, is
    /// still settling). The `xmark.circle.fill` SF Symbol mirrors the canvas's delete affordances.
    @ViewBuilder
    private var deleteButton: some View {
        if isHovering, !phase.isLoading {
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.large)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .buttonStyle(.plain)
            .padding(4)
            .accessibilityLabel("Delete image")
        }
    }

    /// Loads the asset, mirroring the canvas's three-way outcome handling: a terminal miss (missing
    /// or undecodable) is reported and shown as a failed placeholder; a transient fault is retried up
    /// to a cap and then promoted to a reported terminal miss — never left spinning forever (the
    /// review's perpetual-`ProgressView` finding). Cancellation (cell reused / disappeared) just stops.
    private func load() async {
        phase = .loading
        var transientAttempts = 0
        while !Task.isCancelled {
            switch await loadImageData(assetID) {
            case .loaded(let data):
                if let nsImage = NSImage(data: data) {
                    phase = .loaded(Image(nsImage: nsImage))
                } else {
                    reportImageLoadFailure(assetID, .undecodableData)
                    phase = .failed
                }
                return
            case .unavailable:
                reportImageLoadFailure(assetID, .missingAsset)
                phase = .failed
                return
            case .transientFailure:
                transientAttempts += 1
                guard transientAttempts < Self.transientRetryLimit else {
                    reportImageLoadFailure(assetID, .unreadable)
                    phase = .failed
                    return
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
        }
    }
}
