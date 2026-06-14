import AppKit
import SwiftUI

/// Content of the **reusable image-preview window** (ticket 8511D150) — the "click a thumbnail to
/// view the original" half of ticket 0029F466, promoted from a fixed `.sheet` modal to a real,
/// movable, freely-resizable macOS window. It shows a gallery asset's original image at a readable
/// size with pinch-zoom and pan; the window opens sized to the image's aspect ratio within 80% of
/// the board window (initial cap only) and the user may then move and resize it past that.
///
/// **Single reusable window.** The view is hosted by one `Window(id: WindowID.markdownImagePreview)`
/// scene declared in `KanvasRootScene`; opening another thumbnail re-targets the same window. The
/// preview target arrives through shared `@Observable` state (`BoardViewModel.markdownImagePreview`),
/// not an `openWindow` payload (a `Window` scene takes none, and an `Image`/`NSImage` is not
/// transferable). The payload is the ordered `assetIDs` + current index — so the Lightbox navigation
/// (ticket B23D376B, ← / → and the edge `<` / `>` buttons) steps the index with no rework — plus the
/// board window's size captured at open time (the initial-size budget).
///
/// **Re-loads its own bytes — no new I/O class.** The window re-decodes the current asset via the
/// existing `loadImageData(assetID) → Data → NSImage(data:)` path (the same one the gallery cell and
/// canvas use); `intrinsicSize` comes from that decode's `NSImage.size`. No asset is ever re-read by
/// a *new* code path and none is resized — the persisted bytes are unchanged (the ticket's 非対象:
/// no permanent resize). Lives in the `Views/Markdown/` AppKit carve-out so it can decode PNG bytes
/// and reach the host `NSWindow` for initial sizing; no AppKit value type crosses outward.
///
/// **No NSTextView / TextKit.** The image display is pure SwiftUI (`Image` + `MagnifyGesture` +
/// `DragGesture`), so it cannot reintroduce the TextKit-1 layout-hole crash that retired inline
/// rendering (ticket 04568CD4 / 80C0E9C2).
///
/// State machine: it opens in *Fit* (whole image visible, scale == fit, offset zero); a pinch out
/// moves it to *Zoomed* (scale > fit, drag pans); a double-click or a pinch back to the floor
/// returns it to *Fit*. Switching to a different asset resets to *Fit* and re-fits the window.
struct MarkdownImageViewer: View {
    @Bindable var viewModel: BoardViewModel

    /// Closes the host preview window — the single dismissal verb both close routes funnel through
    /// (Esc and the title-bar close button both end at the window vanishing, which clears state once
    /// via `onDisappear`).
    @Environment(\.dismissWindow) private var dismissWindow

    /// Upper zoom bound expressed as a multiple of the fit scale — the ticket's "実用範囲 (~フィット比 8倍)".
    private static let maxZoomFactor: CGFloat = 8

    /// The decoded image to draw, or `nil` while loading / when the asset is unavailable.
    @State private var image: Image?
    /// The decoded image's intrinsic point size (`NSImage.size`) — drives the initial window size
    /// and tightens the letterbox-axis pan clamp. Zero until the first decode.
    @State private var intrinsicSize: CGSize = .zero
    /// The asset id currently shown — drives `task(id:)` reloads and the window re-fit token, so a
    /// new preview target reloads + re-sizes while a zoom/pan change does neither.
    @State private var loadedAssetID: UUID?
    /// The shared request this view last rendered, captured each time the requested target changes.
    /// `onDisappear` hands this snapshot to `clearMarkdownImagePreview(ifMatching:)`, which clears the
    /// shared state only if the live request still equals it — so a fresh open that arrives during the
    /// close animation (a new request published + `openWindow` re-targeting this same window) is not
    /// wiped by the in-flight teardown. The request's monotonic `generation` makes this hold even for
    /// the easiest reopen: re-tapping the *same* thumbnail with the board window untouched, whose
    /// other fields are byte-identical to what this teardown owned.
    @State private var renderedRequest: MarkdownImagePreviewRequest?
    /// True while the current asset is loading; false once loaded or failed.
    @State private var isLoading = false
    /// True when the current asset could not be decoded / is missing — shows a placeholder.
    @State private var didFail = false

    /// Committed zoom scale (1 == fit-to-window). Updated when a pinch ends; the in-flight pinch
    /// multiplies this live via `gestureScale`.
    @State private var scale: CGFloat = 1
    /// Live multiplier during an active `MagnifyGesture`; folded into `scale` on the gesture's end.
    @State private var gestureScale: CGFloat = 1
    /// Committed pan offset (only meaningful while zoomed in). The in-flight drag adds `dragOffset`.
    @State private var offset: CGSize = .zero
    /// Live translation during an active `DragGesture`; folded into `offset` on the drag's end.
    @State private var dragOffset: CGSize = .zero
    /// Live viewport size, captured by a background `GeometryReader`. Drives the pan clamp so a
    /// zoomed image cannot be dragged entirely off-screen (only recovery would be double-click-to-fit).
    @State private var viewportSize: CGSize = .zero

    /// Drives keyboard focus onto the `.focusable()` backdrop so ← / → reach `onKeyPress` the moment
    /// the window opens — `.focusable()` alone does not make a SwiftUI view auto-become first
    /// responder on a fresh window, so without this the arrows are dead until the user clicks the
    /// image or tabs (acceptance criterion '←/→ で前後の画像に切り替わる' out of the box). We also re-assert
    /// it after a step: clicking an edge `<`/`>` button hands focus to that button, after which the
    /// arrows would stop bubbling to the parent; re-focusing here keeps the keys live across clicks.
    @FocusState private var isFocused: Bool

    private var effectiveScale: CGFloat { scale * gestureScale }

    /// The asset the shared request currently targets.
    private var requestedAssetID: UUID? { viewModel.markdownImagePreview?.currentAssetID }

    var body: some View {
        ZStack {
            // Dark backdrop for image legibility (背景は画像視認性のため暗色). Fills the window content;
            // no close-on-tap path any more — the window has its own title-bar close button + Esc.
            Color.black
                .ignoresSafeArea()

            content

            // Edge `<` / `>` navigation buttons (Lightbox, ticket B23D376B): a previous button
            // pinned to the left edge and a next button to the right, each shown only when a
            // neighbouring asset exists (hidden at the ends — no looping — and absent entirely for a
            // single-asset set). They overlay the image inside the dark backdrop.
            navigationButtons
        }
        // Keyboard ← / → step to the previous / next asset (Lightbox, ticket B23D376B). A step past
        // the first/last asset is a no-op in the ViewModel, so the bounds need no guard here. Returns
        // `.handled` only when a step is actually possible, leaving the keys free to bubble otherwise.
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        // Grab focus on open and re-grab whenever the asset changes (e.g. after an edge-button click
        // moved focus to the button), so the arrow keys always reach `onKeyPress` without a manual
        // click first.
        .onAppear { isFocused = true }
        .onChange(of: requestedAssetID) { isFocused = true }
        .onKeyPress(.leftArrow) { stepPreview(by: -1) }
        .onKeyPress(.rightArrow) { stepPreview(by: 1) }
        .background(
            // Read-only viewport probe — feeds the pan clamp; no visual contribution.
            GeometryReader { proxy in
                Color.clear.onAppear { viewportSize = proxy.size }
                    .onChange(of: proxy.size) { _, newSize in viewportSize = newSize }
            }
        )
        // Resize + centre the host window to the image's aspect-fit size on first load and whenever
        // a *different* asset loads; a stable token leaves a user-resized window untouched.
        .background(
            MarkdownPreviewWindowConfigurator(
                contentSize: MarkdownPreviewWindowSizing.initialContentSize(
                    intrinsicSize: intrinsicSize,
                    budget: viewModel.markdownImagePreview?.boardWindowSize ?? .zero
                ),
                sizeToken: image == nil ? nil : loadedAssetID
            )
        )
        .frame(minWidth: MarkdownPreviewWindowSizing.minimumContentSize.width,
               minHeight: MarkdownPreviewWindowSizing.minimumContentSize.height)
        // Esc closes the window (.cancelAction → Escape). Hidden zero-size button so the key wiring
        // exists without a visible affordance competing with the title-bar close button.
        .overlay(escHandler)
        // Load (or reload) whenever the requested asset changes — the single reusable window's
        // content swap. Also runs on first appearance.
        .task(id: requestedAssetID) { await loadRequested() }
        // Single teardown point: both close routes (Esc → dismissWindow and the title-bar close
        // button) end with the window vanishing, so clearing the shared request here keeps the two
        // routes symmetric — the value bag never lingers on the ViewModel past a close.
        //
        // Identity-gated clear: only wipe the shared request if it still equals what this teardown
        // was showing. If a new thumbnail tap published a fresh request (and re-opened this same
        // reusable window) while the dismiss animation was in flight, the live value's monotonic
        // `generation` has advanced past `renderedRequest` — even for a same-image reopen with the
        // board window untouched — so the gate fails and the reopened window keeps the fresh target
        // instead of being wiped empty by the stale teardown (the decoupled close race).
        .onDisappear {
            viewModel.clearMarkdownImagePreview(ifMatching: renderedRequest)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let image {
            image
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .scaleEffect(effectiveScale)
                .offset(x: offset.width + dragOffset.width,
                        y: offset.height + dragOffset.height)
                .gesture(magnify)
                .simultaneousGesture(pan)
                // Double-click toggles back to the fit scale (the ticket's "ダブルクリックでフィットにリセット").
                .onTapGesture(count: 2) { resetToFit() }
                .accessibilityLabel("Original image, pinch to zoom")
        } else if didFail {
            Image(systemName: "photo.badge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(.white.opacity(0.7))
                .accessibilityLabel("Image unavailable")
        } else if isLoading {
            ProgressView()
                .controlSize(.large)
                .tint(.white)
                .accessibilityLabel("Loading image")
        }
    }

    private var escHandler: some View {
        // Esc dismisses the host window — the same outcome as the title-bar close button — rather
        // than merely clearing the shared request (which would leave an empty dark window open).
        // The shared state is cleared once, in `onDisappear`, common to both close routes.
        Button("Close") { dismissWindow(id: WindowID.markdownImagePreview) }
            .keyboardShortcut(.cancelAction)
            .frame(width: 0, height: 0)
            .opacity(0)
            .accessibilityHidden(true)
    }

    /// Decodes the requested asset's bytes via the existing `loadImageData` path and resets the
    /// zoom/pan to *Fit*. A terminal miss is reported (observable degradation) and shown as a
    /// placeholder. Cancellation (window closed / target swapped) just stops. No-op when no asset
    /// is requested (the window is open but empty).
    private func loadRequested() async {
        // Snapshot the request this view is now rendering, so `onDisappear` can tell a teardown that
        // owns the still-current target apart from one the user has already superseded by reopening.
        renderedRequest = viewModel.markdownImagePreview
        guard let assetID = requestedAssetID else {
            image = nil
            didFail = false
            isLoading = false
            return
        }
        isLoading = true
        didFail = false
        switch await viewModel.loadImageData(assetID: assetID) {
        case .loaded(let data):
            if let nsImage = NSImage(data: data) {
                image = Image(nsImage: nsImage)
                intrinsicSize = nsImage.size
                loadedAssetID = assetID
                resetToFit()
            } else {
                viewModel.reportImageLoadFailure(assetID: assetID, reason: .undecodableData)
                fail()
            }
        case .unavailable:
            viewModel.reportImageLoadFailure(assetID: assetID, reason: .missingAsset)
            fail()
        case .transientFailure:
            // A draw-time fetch fault — show the placeholder rather than spin forever; reopening
            // the thumbnail re-tries. Not promoted to the error alert (it is not a user action
            // awaiting a result).
            fail()
        }
        isLoading = false
    }

    private func fail() {
        image = nil
        didFail = true
    }

    /// Pinch zoom, clamped to `[1, maxZoomFactor]` (fit floor, ~8× ceiling). The live multiplier is
    /// kept separate from `scale` so the committed value only updates once per gesture.
    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = scale * value.magnification
                gestureScale = clampedScale(proposed) / scale
            }
            .onEnded { value in
                scale = clampedScale(scale * value.magnification)
                gestureScale = 1
                if scale <= 1 { offset = .zero }
            }
    }

    /// Drag-to-pan, active only when zoomed in (at fit scale there is nothing to pan). The live
    /// translation is clamped on every change (not just on release), so the image stops at the
    /// pan bound under the cursor instead of following past it and rubber-banding back on `onEnded`.
    private var pan: some Gesture {
        DragGesture()
            .onChanged { value in
                guard effectiveScale > 1 else { return }
                let clamped = clampedOffset(CGSize(width: offset.width + value.translation.width,
                                                   height: offset.height + value.translation.height))
                dragOffset = CGSize(width: clamped.width - offset.width,
                                    height: clamped.height - offset.height)
            }
            .onEnded { value in
                guard effectiveScale > 1 else { dragOffset = .zero; return }
                offset = clampedOffset(CGSize(width: offset.width + value.translation.width,
                                              height: offset.height + value.translation.height))
                dragOffset = .zero
            }
    }

    private func clampedScale(_ proposed: CGFloat) -> CGFloat {
        min(max(proposed, 1), Self.maxZoomFactor)
    }

    /// Clamp the committed pan offset so the scaled image cannot be dragged past the point where it
    /// would start leaving its own centred frame. The bound per axis is
    /// `(renderedExtent * effectiveScale - viewport) / 2` — once `renderedExtent * effectiveScale`
    /// exceeds the viewport, that is the slack between the scaled image edge and the viewport edge,
    /// halved because the image is centred. `renderedExtent` is the image's *fitted* extent under
    /// `.scaledToFit()`, resolved from `intrinsicSize` so the letterboxed axis is tightened to its
    /// true rendered range (ticket 4F63D40A). Degenerate metadata falls back to the full viewport.
    private func clampedOffset(_ proposed: CGSize) -> CGSize {
        let rendered = fittedExtent()
        let maxX = max((rendered.width * effectiveScale - viewportSize.width) / 2, 0)
        let maxY = max((rendered.height * effectiveScale - viewportSize.height) / 2, 0)
        return CGSize(width: min(max(proposed.width, -maxX), maxX),
                      height: min(max(proposed.height, -maxY), maxY))
    }

    /// The image's fitted extent under `.scaledToFit()` (at `effectiveScale == 1`): the largest rect
    /// preserving `intrinsicSize`'s aspect ratio that fits inside the viewport. Falls back to the
    /// full viewport on degenerate intrinsic metadata.
    private func fittedExtent() -> CGSize {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0,
              viewportSize.width > 0, viewportSize.height > 0 else {
            return viewportSize
        }
        let fitScale = min(viewportSize.width / intrinsicSize.width,
                           viewportSize.height / intrinsicSize.height)
        return CGSize(width: intrinsicSize.width * fitScale,
                      height: intrinsicSize.height * fitScale)
    }

    private func resetToFit() {
        withAnimation(.easeInOut(duration: 0.2)) {
            scale = 1
            gestureScale = 1
            offset = .zero
            dragOffset = .zero
        }
    }
}
