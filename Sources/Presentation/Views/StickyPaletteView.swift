import SwiftUI

/// Miro-style sticky tray floated on the canvas's left edge. Each swatch is a drag source carrying
/// its preset id as a `"preset:<uuid>"` string; the canvas (`CanvasNSView`) is the drop destination
/// and creates a sticky of that preset's size + colour at the drop point. The tray itself does not
/// touch the ViewModel — creation flows through the canvas drop → `CanvasActionHandler`.
struct StickyPaletteView: View {
    /// The board's managed presets (label / colour / absolute size), in display order. Edited in
    /// Settings → Canvas; surfaced read-only here.
    let presets: [StickyPresetResponse]

    /// Largest preset maps to this on-screen width; the others scale proportionally so the swatches
    /// read as relative sizes. Falls back gracefully when every preset is the same size.
    private static let maxPreviewWidth: Double = 44
    private var maxPresetWidth: Double { max(presets.map(\.width).max() ?? 1, 1) }
    private func previewWidth(_ preset: StickyPresetResponse) -> Double {
        Self.maxPreviewWidth * (preset.width / maxPresetWidth)
    }
    private func previewHeight(_ preset: StickyPresetResponse) -> Double {
        // Preserve each preset's own aspect ratio within the scaled-down preview.
        previewWidth(preset) * (preset.height / max(preset.width, 1))
    }

    var body: some View {
        VStack(spacing: 14) {
            ForEach(presets) { preset in
                swatch(preset)
            }
            Divider().frame(width: Self.maxPreviewWidth)
            ForEach(ShapeRegistry.paletteItems) { item in
                shapeSwatch(item)
            }
            textSwatch
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 10)
        .background(.bar, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator, lineWidth: 0.5))
        .padding(10)
    }

    /// Shape tool — drags a `"shape:<kind>"` payload that the canvas drop handler decodes and turns
    /// into a new shape at the drop point (mirrors the sticky swatch drag flow).
    private func shapeSwatch(_ item: ShapePaletteItem) -> some View {
        Image(systemName: item.symbolName)
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: Self.maxPreviewWidth, height: Self.maxPreviewWidth * 0.7)
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: ShapeRegistry.dragPayload(forKind: item.kind) as NSString) }
            .help("Drag to add \(item.label)")
    }

    /// Free-text tool — drags the `"text"` payload that the canvas drop handler turns into an empty,
    /// immediately-editable free-text object at the drop point (background/border-less plain text).
    private var textSwatch: some View {
        Image(systemName: "textformat")
            .font(.system(size: 20))
            .foregroundStyle(.secondary)
            .frame(width: Self.maxPreviewWidth, height: Self.maxPreviewWidth * 0.7)
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(object: CanvasNSView.textPayload as NSString) }
            .help("Drag to add text")
    }

    private func swatch(_ preset: StickyPresetResponse) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: preset.colorHex))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(.separator, lineWidth: 0.5))
            .overlay(
                Text(preset.label)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.readableForeground(onHex: preset.colorHex))
            )
            .frame(width: previewWidth(preset), height: previewHeight(preset))
            .frame(width: Self.maxPreviewWidth, height: previewHeight(preset))
            .contentShape(Rectangle())
            .onDrag {
                NSItemProvider(object: "\(CanvasNSView.stickyPresetPayloadPrefix)\(preset.id.uuidString)" as NSString)
            }
            .help(preset.label.isEmpty
                  ? "Drag to add a sticky"
                  : "Drag to add a \(preset.label) sticky")
    }
}
