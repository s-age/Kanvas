import Foundation

// MARK: - Free-text mapping
//
// Kept in a same-type extension (encode + decode together) so the round-trip cannot drift, and split
// out of the primary file so each stays within the `type_body_length` budget.

extension BoardSnapshotMapper {

    /// Decodes free-text objects. A missing colour/font falls back to the default style; the entity
    /// re-clamps the font size on construction (the "persisted value is untrusted input" rule). A
    /// missing `sortIndex` falls back to array order.
    static func textEntities(_ dtos: [TextDTO]) -> [CanvasText] {
        dtos.enumerated().map { index, text in
            CanvasText(
                id: text.id,
                cardID: text.cardID,
                content: text.content,
                position: CanvasPosition(x: text.positionX, y: text.positionY),
                size: TextSize(width: text.width, height: text.height),
                style: CanvasTextStyle(
                    colorHex: text.textColorHex ?? CanvasTextStyle.defaultColorHex,
                    fontSize: text.fontSize ?? CanvasTextStyle.defaultFontSize
                ),
                sortIndex: text.sortIndex ?? index
            )
        }
    }

    static func textDTO(_ text: CanvasText) -> TextDTO {
        TextDTO(
            id: text.id,
            cardID: text.cardID,
            content: text.content,
            positionX: text.position.x,
            positionY: text.position.y,
            width: text.size.width,
            height: text.size.height,
            textColorHex: text.style.colorHex,
            fontSize: text.style.fontSize,
            sortIndex: text.sortIndex
        )
    }
}
