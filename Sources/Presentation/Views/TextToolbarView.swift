import SwiftUI

/// Top toolbar shown while a free-text object is selected on the canvas — text colour and a
/// font-size stepper. A free-text object has no background or border, so there is no fill control
/// (unlike `StickyToolbarView` / `ShapeToolbarView`). Edits flow through `BoardViewModel` to the
/// text's persisted `CanvasTextStyle`.
struct TextToolbarView: View {
    @Bindable var viewModel: BoardViewModel
    let text: TextResponse

    var body: some View {
        HStack(spacing: 6) {
            colorSection
            Divider().frame(height: 20)
            fontSizeStepper
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var colorSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("textformat", help: "Text color")
            PaletteColorPicker(selection: colorHexBinding)
        }
    }

    private var colorHexBinding: Binding<String> {
        Binding(
            get: { text.textColorHex },
            set: { hex in
                guard hex.caseInsensitiveCompare(text.textColorHex) != .orderedSame else { return }
                Task { await viewModel.setTextColor(id: text.id, colorHex: hex) }
            }
        )
    }

    private var fontSizeStepper: some View {
        HStack(spacing: 4) {
            Image(systemName: "textformat.size")
            Stepper(
                value: Binding(
                    get: { text.fontSize },
                    set: { newValue in
                        Task { await viewModel.setTextFontSize(id: text.id, fontSize: newValue) }
                    }
                ),
                in: text.minFontSize...text.maxFontSize,
                step: 1
            ) {
                Text("\(Int(text.fontSize)) pt")
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }
}
