import Foundation

/// Identifiers for the app's SwiftUI window scenes.
///
/// Shared between the `App`-layer scene declarations (`Window(id:)`) and the Presentation
/// views that open/dismiss them (`openWindow(id:)` / `dismissWindow(id:)`). Centralized
/// because those APIs silently no-op on an unknown id: a raw-string rename at one of the
/// three call sites would compile cleanly yet break the open/dismiss wiring with no error.
enum WindowID {
    static let settings = "settings"
    /// The single reusable Markdown image-preview window (ticket 8511D150). One `Window(id:)`
    /// (not a `WindowGroup`) — opening another image re-targets the same window's content.
    static let markdownImagePreview = "markdown-image-preview"
}
