import Foundation

/// Shared validation for label requests — the Request layer is the validation boundary, and a
/// label's colour drives canvas drawing directly, so the format is enforced here rather than left
/// to a downstream colour-parse fallback.
enum LabelValidation {
    static func validate(name: String, colorHex: String) throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.emptyLabelName
        }
        try validate(colorHex: colorHex)
    }

    static func validate(colorHex: String) throws {
        guard colorHex.count == 6, colorHex.allSatisfy(\.isHexDigit) else {
            throw ValidationError.invalidColorHex
        }
    }
}
