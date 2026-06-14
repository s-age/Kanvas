import Foundation

struct AddImageRequest: ValidatableRequest {
    let cardID: UUID
    /// PNG-encoded pixels to persist as the image's sidecar asset. Validated non-empty.
    let imageData: Data
    /// Drop/paste point in world coordinates — becomes the image's centre.
    let positionX: Double
    let positionY: Double
    /// Source pixel dimensions, used to fit an initial on-canvas size and record the aspect ratio.
    let naturalWidth: Double
    let naturalHeight: Double

    func validate() throws {
        guard !imageData.isEmpty else { throw ValidationError.emptyImageData }
        try ContentSizeValidation.validate(imageByteCount: imageData.count)
        // `positionX`/`positionY` flow unclamped into `CanvasPosition`; reject non-finite up front so
        // a boundary-less MCP caller (`canvas_image_add`) cannot persist NaN/Inf (ticket 4FD6D166).
        // `naturalWidth`/`naturalHeight` are clamped on the `ImageSize` entity `init`.
        try NumericBoundsValidation.validate(finiteCoordinates: positionX, positionY)
    }
}
