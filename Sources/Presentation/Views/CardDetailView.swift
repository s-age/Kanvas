import SwiftUI

struct CardDetailView: View {
    @Bindable var viewModel: BoardViewModel

    /// Live palette from the current board's global settings, falling back to the (value-stable)
    /// seeded default when no board is loaded or the palette is empty. Read in `body` (not
    /// snapshotted) so the canvas toolbars always reflect the latest saved palette without a
    /// separate load cycle.
    private var currentPalette: [PaletteColorResponse] {
        let responses = viewModel.board?.settings.global.colorPalette ?? []
        return responses.isEmpty ? PalettePresentationDefaults.swatches : responses
    }

    var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                // The canvas is a self-drawn NSView that paints over any in-pane SwiftUI
                // sibling, so the toolbar is floated on top via .overlay rather than stacked
                // above it in a VStack.
                CanvasRepresentable(viewModel: viewModel)
                    .overlay(alignment: .top) {
                        // Sticky and shape selection are mutually exclusive, so at most one toolbar
                        // shows at a time.
                        if let sticky = viewModel.selectedSticky {
                            StickyToolbarView(viewModel: viewModel, sticky: sticky)
                        } else if let shape = viewModel.selectedShape {
                            ShapeToolbarView(viewModel: viewModel, shape: shape)
                        } else if let text = viewModel.selectedText {
                            TextToolbarView(viewModel: viewModel, text: text)
                        } else if let connector = viewModel.selectedConnector {
                            ConnectorToolbarView(viewModel: viewModel, connector: connector)
                        }
                    }
                    .overlay(alignment: .leading) {
                        StickyPaletteView(presets: viewModel.stickyPresets)
                    }
                    .overlay {
                        if viewModel.isLabelManagerPresented {
                            // A full-area, near-invisible catcher behind the panel: a click
                            // anywhere outside the panel dismisses it (the panel and the system
                            // colour picker — a separate window — stay unaffected).
                            ZStack(alignment: .topTrailing) {
                                Color.black.opacity(0.001)
                                    .contentShape(Rectangle())
                                    .onTapGesture { viewModel.closeLabelManager() }
                                LabelManagerView(viewModel: viewModel)
                            }
                        }
                    }
                if viewModel.isMarkdownExpanded {
                    MarkdownEditorView(viewModel: viewModel)
                        .frame(minWidth: 300)
                }
            }
        }
        .toolbar {
            Button {
                viewModel.isMarkdownExpanded.toggle()
            } label: {
                Image(systemName: "doc.text")
            }
            .help(viewModel.isMarkdownExpanded ? "Hide Notes" : "Show Notes")
        }
        // Inject the live palette so all canvas toolbars and LabelManagerView read it via
        // @Environment(\.colorPalette) without needing an explicit prop-drill.
        .environment(\.colorPalette, currentPalette)
    }
}
