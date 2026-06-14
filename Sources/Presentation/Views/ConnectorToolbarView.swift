import SwiftUI

/// Top toolbar shown while a connector is selected on the canvas — endpoint cap (line / arrow),
/// routing (straight / orthogonal / curved), stroke colour, and a stroke-width stepper. Mirrors
/// `ShapeToolbarView`; edits flow through `BoardViewModel` to the connector's persisted style.
struct ConnectorToolbarView: View {
    @Bindable var viewModel: BoardViewModel
    let connector: ConnectorResponse
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            capSection
            Divider().frame(height: 20)
            routingSection
            Divider().frame(height: 20)
            strokeSection
            Divider().frame(height: 20)
            strokeWidthStepper
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private var capSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("arrow.up.right", help: "Endpoint")
            iconToggle(symbol: "minus", help: "Line", isSelected: connector.cap == .line) {
                Task { await viewModel.setConnectorCap(id: connector.id, cap: ConnectorCapResponse.line.rawValue) }
            }
            iconToggle(symbol: "arrow.right", help: "Arrow", isSelected: connector.cap == .arrow) {
                Task { await viewModel.setConnectorCap(id: connector.id, cap: ConnectorCapResponse.arrow.rawValue) }
            }
        }
    }

    private var routingSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("point.topleft.down.to.point.bottomright.curvepath", help: "Routing")
            iconToggle(symbol: "line.diagonal", help: "Straight",
                       isSelected: connector.routing == .straight) {
                set(routing: .straight)
            }
            iconToggle(symbol: "arrow.turn.right.down", help: "Orthogonal",
                       isSelected: connector.routing == .elbow) {
                set(routing: .elbow)
            }
            iconToggle(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", help: "Curved",
                       isSelected: connector.routing == .curve) {
                set(routing: .curve)
            }
        }
    }

    private func set(routing: ConnectorRoutingResponse) {
        Task { await viewModel.setConnectorRouting(id: connector.id, routing: routing.rawValue) }
    }

    private var strokeSection: some View {
        HStack(spacing: 6) {
            ToolbarSectionIcon("scribble", help: "Stroke color")
            // Clearable: nil = unset → the canvas draws the adaptive default, and the picker shows
            // `unsetDefaultColor` + a Clear button. Reusing this control (the sticky-fill pattern)
            // means an explicit pick — including pure black — writes through, because its same-value
            // guard compares against the resolved default, not a black placeholder.
            ClearablePaletteColorPicker(
                selection: strokeColorHexBinding,
                defaultColor: unsetDefaultColor
            )
        }
    }

    /// The colour shown for an **unset** stroke: the canvas resolves it adaptively (`#333`/`#ddd`) by
    /// the live background, which is only ever unset on a system-background board — so the SwiftUI
    /// `colorScheme` is the faithful pick here, with no AppKit luminance read. (A genuinely-unset
    /// stroke on a configured-background board is a rare legacy case; the swatch is a placeholder.)
    private var unsetDefaultColor: Color {
        Color(hex: colorScheme == .dark ? ConnectorAppearance.onDarkStrokeHex
                                        : ConnectorAppearance.onLightStrokeHex)
    }

    /// Per-connector stroke (nil = unset → adaptive). The setter writes a concrete hex; the built-in
    /// Clear button writes nil to restore the adaptive default.
    private var strokeColorHexBinding: Binding<String?> {
        Binding(
            get: { connector.strokeColorHex },
            set: { hex in
                Task { await viewModel.setConnectorStrokeColor(id: connector.id, colorHex: hex) }
            }
        )
    }

    private var strokeWidthStepper: some View {
        HStack(spacing: 4) {
            Image(systemName: "lineweight")
            Stepper(
                value: Binding(
                    get: { connector.strokeWidth },
                    set: { newValue in
                        Task { await viewModel.setConnectorStrokeWidth(id: connector.id, width: newValue) }
                    }
                ),
                in: connector.minStrokeWidth...connector.maxStrokeWidth,
                step: 1
            ) {
                Text("\(Int(connector.strokeWidth)) pt")
                    .monospacedDigit()
                    .frame(minWidth: 44, alignment: .leading)
            }
        }
    }

    private func iconToggle(symbol: String, help: String, isSelected: Bool,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 24, height: 20)
                .background(isSelected ? Color.accentColor.opacity(0.2) : .clear)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: isSelected ? 1.5 : 0))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
