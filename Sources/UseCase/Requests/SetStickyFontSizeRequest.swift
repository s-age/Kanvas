import Foundation

struct SetStickyFontSizeRequest: ValidatableRequest {
    let stickyID: UUID
    let fontSize: Double

    func validate() throws {
        try NumericBoundsValidation.validate(
            fontSize: fontSize, in: StickyTextStyle.minFontSize...StickyTextStyle.maxFontSize
        )
    }
}
