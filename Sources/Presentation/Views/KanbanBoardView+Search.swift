import SwiftUI

// The toolbar's centre card-search field, split into its own file so it no longer lives in
// `KanbanBoardView+BoardPicker.swift` (a search field is not a picker — PR #123 r1-4). It binds the
// `BoardViewModel.searchText`, which debounces a `SearchCardsUseCase` call into `matchedCardIDs`
// (ticket 59B10FBA); the kanban view filters each column's cards through that set.

extension KanbanBoardView {

    /// The header's centre card-search field — live-filters the active board's cards by title /
    /// Markdown body / sticky text / card UUID (ticket 59B10FBA). A magnifier leads it; a clear "×"
    /// trails when non-empty, and Esc clears it too. UI strings are English (UI-English-only規約).
    var cardSearchField: some View {
        // One capsule only. The OS-standard rounded capsule comes from the *toolbar's*
        // `.principal`-placement chrome that wraps this whole HStack — not from the `TextField`,
        // whose own bezel `.textFieldStyle(.plain)` strips. (Verified at runtime, light + dark,
        // 要・実機確認: the magnifier — an HStack sibling outside the field — renders *inside* the
        // surviving capsule, which it could not if the capsule were the field's own bezel.) The
        // former self-drawn `Color.secondary.opacity(0.12)` background + `clipShape` stacked a
        // second, smaller capsule inside the toolbar one, leaving a visible gap band top/bottom
        // (ticket B9A3CEF5). Dropping the self-drawn layer and its inflating padding leaves a
        // single native capsule — default colours, focus ring, and light/dark looks left to the OS.
        //
        // The magnifier and clear "×" sit inside that toolbar capsule alongside the `TextField`. A
        // small symmetric `.padding(.horizontal, 6)` on the HStack keeps those two icons from
        // butting flush against the capsule edge without re-introducing a second capsule (no
        // background / clipShape / vertical inset) — PR #140 r1-1.
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.caption)
            TextField("Search cards…", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .frame(minWidth: 180, idealWidth: 240)
                .onExitCommand { viewModel.clearSearch() }
            if !viewModel.searchText.isEmpty {
                Button {
                    viewModel.clearSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Clear search")
            }
        }
        .padding(.horizontal, 6)
    }
}
