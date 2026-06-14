import AppKit
import SwiftUI

/// Window-plumbing helpers for the Markdown image-preview window (ticket 8511D150). Both live in
/// the `Views/Markdown/` AppKit carve-out — the only Presentation zone allowed to touch `NSWindow`
/// — so the rest of Presentation stays AppKit-free. They carry no domain logic: one reads a window
/// size, the other applies one. No AppKit value type crosses a ViewModel/DI boundary (the size is
/// a plain `CGSize`).
enum MarkdownPreviewWindowSizing {
    /// The minimum content size of the preview window — the resize floor (現状踏襲: 480×360). The
    /// initial aspect-fit size is clamped up to at least this so a small image still opens usably.
    static let minimumContentSize = CGSize(width: 480, height: 360)

    /// The board (Kanban) window's current content size, used as the initial-size budget for the
    /// preview. Found by excluding the auxiliary windows (settings, the preview window itself, and
    /// non-titled panels) and taking the first remaining visible titled window — in this
    /// single-board app that is the board window. Returns `.zero` if none is found, in which case
    /// the caller falls back to the minimum size.
    @MainActor
    static func boardWindowContentSize() -> CGSize {
        let candidate = NSApp.windows.first { window in
            window.isVisible
                && window.styleMask.contains(.titled)
                && window.identifier?.rawValue != WindowID.settings
                && window.identifier?.rawValue != WindowID.markdownImagePreview
                // SwiftUI tags scene windows with an identifier prefixed by the scene id; match the
                // settings/preview scenes by prefix too, since SwiftUI may suffix them.
                && !(window.identifier?.rawValue.hasPrefix(WindowID.settings) ?? false)
                && !(window.identifier?.rawValue.hasPrefix(WindowID.markdownImagePreview) ?? false)
        }
        return candidate?.contentLayoutRect.size ?? .zero
    }

    /// The largest content size that preserves `intrinsicSize`'s aspect ratio while fitting inside
    /// `budget * 0.8`, clamped up to `minimumContentSize`. Small images are *enlarged* to the 80%
    /// budget (ticket: 小さい画像も拡大する); the 80% is an initial cap only — the user may resize past it.
    /// Falls back to `minimumContentSize` on a degenerate intrinsic size or an unavailable budget.
    static func initialContentSize(intrinsicSize: CGSize, budget: CGSize) -> CGSize {
        guard intrinsicSize.width > 0, intrinsicSize.height > 0,
              budget.width > 0, budget.height > 0 else {
            return minimumContentSize
        }
        let cap = CGSize(width: budget.width * 0.8, height: budget.height * 0.8)
        let fitScale = min(cap.width / intrinsicSize.width, cap.height / intrinsicSize.height)
        let fitted = CGSize(width: intrinsicSize.width * fitScale,
                            height: intrinsicSize.height * fitScale)
        return CGSize(width: max(fitted.width, minimumContentSize.width),
                      height: max(fitted.height, minimumContentSize.height))
    }
}

/// Zero-area bridge view that, on first appearance and on each `sizeToken` change, sets the host
/// `NSWindow`'s minimum size and resizes it to `contentSize` (centring the first time). Driven by
/// the preview window content so the window opens at the aspect-fit initial size and re-fits when a
/// different image is loaded — while leaving the user free to resize afterwards (we only resize on
/// a *new* token, never on every render).
struct MarkdownPreviewWindowConfigurator: NSViewRepresentable {
    /// The desired content size for the current image.
    let contentSize: CGSize
    /// Changes exactly when a new image should re-fit the window (the asset id). A stable token
    /// across renders means "leave the window where the user put it".
    let sizeToken: UUID?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.apply(contentSize: contentSize, sizeToken: sizeToken, host: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.apply(contentSize: contentSize, sizeToken: sizeToken, host: nsView)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    @MainActor
    final class Coordinator {
        /// The token last applied — guards against re-resizing on unrelated re-renders (e.g. a
        /// zoom/pan state change), which would yank a user-resized window back to the fit size.
        private var appliedToken: UUID?

        func apply(contentSize: CGSize, sizeToken: UUID?, host: NSView) {
            guard let token = sizeToken, token != appliedToken else { return }
            // The window may not be attached on the very first `makeNSView`; defer to the next
            // runloop turn so `host.window` is populated, then resize + centre.
            DispatchQueue.main.async { [weak host] in
                guard let window = host?.window else { return }
                self.appliedToken = token
                let isFirstSizing = window.frame.size == .zero || !window.isVisible
                window.contentMinSize = MarkdownPreviewWindowSizing.minimumContentSize
                window.setContentSize(contentSize)
                if isFirstSizing { window.center() }
            }
        }
    }
}
