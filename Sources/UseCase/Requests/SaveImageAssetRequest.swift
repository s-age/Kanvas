import Foundation

/// Persists image bytes as a standalone sidecar asset and returns the new asset id — **without**
/// placing a `CanvasImage` on any board (unlike `AddImageRequest`). Used by the Markdown editor's
/// drag-drop image import: the returned id is embedded in the card body as a
/// `kanvas-asset://<id>` reference, and the board is never mutated here. Validates the same non-empty
/// + size bounds as `AddImageRequest`, since the bytes flow through the same asset store.
struct SaveImageAssetRequest: ValidatableRequest {
    /// PNG-encoded pixels to persist as the asset. Validated non-empty and within the size cap.
    /// This is the *only* input — a Markdown reference (`kanvas-asset://<id>`) holds no size, so the
    /// drop site's source dimensions are intentionally not threaded here (unlike `AddImageRequest`,
    /// which places a sized `CanvasImage`).
    let imageData: Data

    func validate() throws {
        guard !imageData.isEmpty else { throw ValidationError.emptyImageData }
        try ContentSizeValidation.validate(imageByteCount: imageData.count)
    }
}
