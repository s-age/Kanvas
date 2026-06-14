import Foundation

/// A pasted/dropped image's bytes plus the source pixel dimensions, carried together from the
/// canvas to the ViewModel so `addImage` stays within the parameter-count budget. A ViewModel-facing
/// vocabulary type (consumed by `addImage`), so it lives in `Shared/` rather than the AppKit-permitted
/// `Canvas/` folder — it carries no AppKit value type.
struct CanvasImagePayload: Sendable {
    let pngData: Data
    let naturalWidth: Double
    let naturalHeight: Double
}
