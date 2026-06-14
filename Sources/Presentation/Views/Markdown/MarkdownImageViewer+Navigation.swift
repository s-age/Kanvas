import SwiftUI

/// Lightbox navigation for the reusable image-preview window (ticket B23D376B): keyboard ← / → and
/// edge `<` / `>` buttons step to the previous / next asset in the gallery's ordered set. The shared
/// `MarkdownImagePreviewRequest` already carries the full `assetIDs` + current index (designed for
/// this in ticket 8511D150), so stepping is just moving the index — `BoardViewModel`
/// `.stepMarkdownImagePreview(by:)` clamps it (no looping) and the window's `task(id:)` re-decodes
/// the new asset and re-fits zoom/pan. The keyboard wiring lives on the parent view; this extension
/// holds the visual button affordances and the shared step helper.
extension MarkdownImageViewer {
    /// The left/right edge step buttons. Each is present only when there is somewhere to step (so a
    /// single-asset preview shows neither, and the ends hide the unavailable direction — the ticket's
    /// 端の扱い: 無効表示, ループしない). Pinned to the leading/trailing edge so the centred image is never
    /// occluded by the active button.
    @ViewBuilder
    var navigationButtons: some View {
        let preview = viewModel.markdownImagePreview
        HStack {
            if preview?.hasPrevious == true {
                edgeButton(systemName: "chevron.left", label: "Previous image") { stepPreview(by: -1) }
            }
            Spacer()
            if preview?.hasNext == true {
                edgeButton(systemName: "chevron.right", label: "Next image") { stepPreview(by: 1) }
            }
        }
        .padding(.horizontal, 12)
    }

    private func edgeButton(systemName: String,
                            label: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title)
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    /// Steps the shared preview index via the ViewModel (clamped, no loop) and returns the
    /// `onKeyPress` result: `.handled` when a step was possible, `.ignored` otherwise so the arrow
    /// key can bubble. The `viewModel.stepMarkdownImagePreview` call is itself a no-op at the ends.
    @discardableResult
    func stepPreview(by delta: Int) -> KeyPress.Result {
        let canStep = delta < 0
            ? viewModel.markdownImagePreview?.hasPrevious == true
            : viewModel.markdownImagePreview?.hasNext == true
        guard canStep else { return .ignored }
        viewModel.stepMarkdownImagePreview(by: delta)
        return .handled
    }
}
