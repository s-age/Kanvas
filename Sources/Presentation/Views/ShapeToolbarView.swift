import SwiftUI

/// Top toolbar shown while a shape is selected on the canvas — stroke colour, fill colour (with a
/// "no fill" option), and a stroke-width stepper. Mirrors `StickyToolbarView`; edits flow through
/// `BoardViewModel` to the shape's persisted `CanvasShapeStyle`. Fill controls are hidden for a
/// line (a line has no fill).
struct ShapeToolbarView: View {
    @Bindable var viewModel: BoardViewModel
    let shape: ShapeResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                strokeSection
                Divider().frame(height: 20)
                strokeWidthStepper
            }
            if shape.topology != .segment {
                fillSection
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var strokeSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("scribble", help: "Stroke color")
            PaletteColorPicker(selection: strokeColorHexBinding)
        }
    }

    private var fillSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("paintbrush.fill", help: "Fill color")
            noFillSwatch
            PaletteColorPicker(selection: fillColorHexBinding)
        }
    }

    private var strokeColorHexBinding: Binding<String> {
        Binding(
            get: { shape.strokeColorHex },
            set: { hex in
                guard hex.caseInsensitiveCompare(shape.strokeColorHex) != .orderedSame else { return }
                Task { await viewModel.setShapeStrokeColor(id: shape.id, colorHex: hex) }
            }
        )
    }

    private var fillColorHexBinding: Binding<String> {
        Binding(
            get: { shape.fillColorHex ?? "000000" },
            set: { hex in
                guard hex.caseInsensitiveCompare(shape.fillColorHex ?? "") != .orderedSame else { return }
                Task { await viewModel.setShapeFillColor(id: shape.id, colorHex: hex) }
            }
        )
    }

    /// Clears the fill (stroke-only). Selected when the shape currently has no fill.
    private var noFillSwatch: some View {
        Button {
            Task { await viewModel.setShapeFillColor(id: shape.id, colorHex: nil) }
        } label: {
            Image(systemName: "circle.slash")
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .overlay(Circle().stroke(Color.accentColor, lineWidth: shape.fillColorHex == nil ? 2 : 0).padding(-2))
        }
        .buttonStyle(.plain)
        .help("No fill")
    }

    private var strokeWidthStepper: some View {
        HStack(spacing: 4) {
            Image(systemName: "lineweight")
            Stepper(
                value: Binding(
                    get: { shape.strokeWidth },
                    set: { newValue in
                        Task { await viewModel.setShapeStrokeWidth(id: shape.id, width: newValue) }
                    }
                ),
                in: shape.minStrokeWidth...shape.maxStrokeWidth,
                step: 1
            ) {
                Text("\(Int(shape.strokeWidth)) pt")
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }
}
