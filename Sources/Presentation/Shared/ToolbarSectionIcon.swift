import SwiftUI

/// A fixed-width leading icon for a canvas selection-toolbar section. The fixed frame keeps swatch
/// rows aligned across stacked sections (e.g. the sticky toolbar's Text / Background rows) no matter
/// how wide the SF Symbol's intrinsic glyph is (`textformat.abc` is much wider than `paintbrush.fill`).
struct ToolbarSectionIcon: View {
    private let systemName: String
    private let help: String

    init(_ systemName: String, help: String) {
        self.systemName = systemName
        self.help = help
    }

    var body: some View {
        Image(systemName: systemName)
            .foregroundStyle(.secondary)
            .frame(width: 26)
            .help(help)
    }
}
