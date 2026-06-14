import Foundation

struct SetTextFontSizeRequest: ValidatableRequest {
    let textID: UUID
    let fontSize: Double

    func validate() throws {
        try NumericBoundsValidation.validate(
            fontSize: fontSize, in: CanvasTextStyle.minFontSize...CanvasTextStyle.maxFontSize
        )
    }
}
