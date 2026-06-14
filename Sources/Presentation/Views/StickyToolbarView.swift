import SwiftUI

/// Top toolbar shown while a sticky is selected on the canvas — text-colour picker, background
/// (fill) colour picker, and a numeric font-size stepper. Text colour persists to the sticky's
/// `StickyTextStyle`; the fill colour persists to `Sticky.fillColorHex` (clearable back to the
/// board's free/task default). Both colour wells guard same-value write-backs so a redraw never
/// re-commits the current colour.
struct StickyToolbarView: View {
    @Bindable var viewModel: BoardViewModel
    let sticky: StickyResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                ToolbarSectionIcon("textformat.abc", help: "Text color")
                PaletteColorPicker(selection: textColorHexBinding)
                Divider().frame(height: 20)
                fontSizeStepper
            }
            HStack(spacing: 6) {
                ToolbarSectionIcon("paintbrush.fill", help: "Background color")
                ClearablePaletteColorPicker(
                    selection: fillColorHexBinding,
                    defaultColor: Color(hex: defaultFillHex)
                )
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    /// The board's effective default fill for this sticky (free/task override, else the built-in
    /// default) — shown in the background well while the sticky has no per-sticky fill, mirroring
    /// what the canvas actually draws.
    private var defaultFillHex: String {
        let canvas = viewModel.board?.settings.canvas
        let override = sticky.isTask ? canvas?.taskStickyColorHex : canvas?.freeStickyColorHex
        return override ?? (sticky.isTask
            ? StickyAppearance.taskStickyDefaultHex
            : StickyAppearance.freeStickyDefaultHex)
    }

    private var textColorHexBinding: Binding<String> {
        Binding(
            get: { sticky.textColorHex },
            set: { hex in
                guard hex.caseInsensitiveCompare(sticky.textColorHex) != .orderedSame else { return }
                Task { await viewModel.setStickyTextColor(id: sticky.id, colorHex: hex) }
            }
        )
    }

    /// Reads the per-sticky fill (nil = "use board default"). The setter writes a concrete hex;
    /// clearing back to nil restores the board default and is handled by the built-in Clear button.
    private var fillColorHexBinding: Binding<String?> {
        Binding(
            get: { sticky.fillColorHex },
            set: { hex in
                Task { await viewModel.setStickyFillColor(id: sticky.id, colorHex: hex) }
            }
        )
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 4) {
            Image(systemName: "textformat.size")
            Stepper(
                value: Binding(
                    get: { sticky.fontSize },
                    set: { newValue in
                        Task { await viewModel.setStickyFontSize(id: sticky.id, fontSize: newValue) }
                    }
                ),
                in: StickyAppearance.minFontSize...StickyAppearance.maxFontSize,
                step: 1
            ) {
                Text("\(Int(sticky.fontSize)) pt")
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }
}
