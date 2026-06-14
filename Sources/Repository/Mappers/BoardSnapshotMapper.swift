import Foundation

/// A transport-recovery note describing one coercion or drop the snapshot decoder applied to a
/// persisted board (a malformed schedule discarded, a dangling connector filtered out, a connector
/// field with an unknown raw value forced to its default). Returned from `decode(_:)` so the
/// Repository can log each via the injected diagnostics port: a read-time recovery in this
/// whole-blob store is a **latent write** — the next save of *any* part of the board persists the
/// coerced/dropped value permanently, with no further decode failure to observe — so it must never
/// stay silent (`arch-repository.md` → "Latent write-back in a whole-blob model"). The note carries
/// no entity reference (it is logged and discarded); preventing the write-back itself is out of
/// scope here (ticket FF49E147 covers observability only).
struct SnapshotRecovery: Equatable, Sendable {
    /// Public summary — field names / kinds, safe to surface in `Console.app`.
    let summary: String
    /// Private detail — ids and the raw on-disk value that may embed user content; logged redacting.
    let detail: String
}

extension SnapshotRecovery {
    /// A card's persisted schedule could not be reconstructed and was discarded.
    static func scheduleDropped(cardID: UUID, reason: String, rawKind: String) -> Self {
        SnapshotRecovery(summary: "card schedule dropped: \(reason)",
                         detail: "card=\(cardID) kind=\(rawKind)")
    }

    /// A connector referencing an absent endpoint sticky was filtered out on load.
    static func connectorDropped(connectorID: UUID, sourceStickyID: UUID, targetStickyID: UUID) -> Self {
        SnapshotRecovery(summary: "connector dropped: endpoint sticky absent",
                         detail: "connector=\(connectorID) source=\(sourceStickyID) target=\(targetStickyID)")
    }

    /// A connector field held an unknown raw value and was forced to its default.
    static func connectorFieldCoerced(connectorID: UUID, field: String, raw: String,
                                      fallback: String) -> Self {
        SnapshotRecovery(summary: "connector \(field) coerced to default",
                         detail: "connector=\(connectorID) raw=\(raw) fallback=\(fallback)")
    }
}

enum BoardSnapshotMapper {
    private enum ScheduleKind {
        static let deadline = "deadline"
        static let period = "period"
    }

    /// Decodes a snapshot into a `BoardState` **and** the transport recoveries applied during decode
    /// (see `SnapshotRecovery`). This is the single decode entry point that surfaces recoveries; the
    /// Repository calls it and logs each note. Detection lives here (one pass, co-located with the
    /// encode side) — the *decision* to log/recover is the Repository's.
    static func decode(_ dto: BoardSnapshotDTO) -> (state: BoardState, recoveries: [SnapshotRecovery]) {
        var recoveries: [SnapshotRecovery] = []
        let board = Board(id: dto.board.id, title: dto.board.title)
        let columns = dto.columns.map { col in
            Column(
                id: col.id,
                boardID: col.boardID,
                title: col.title,
                sortIndex: col.sortIndex,
                isCompletionColumn: col.isCompletionColumn ?? false,
                headerColorHex: col.headerColorHex,
                headerTextColorHex: col.headerTextColorHex,
                bodyColorHex: col.bodyColorHex,
                headerBorderColorHex: col.headerBorderColorHex,
                bodyBorderColorHex: col.bodyBorderColorHex,
                indicatorColorHex: col.indicatorColorHex
            )
        }
        let cards = dto.cards.map { cardEntity($0, into: &recoveries) }
        let labels = (dto.labels ?? []).map { label in
            StickyLabel(id: label.id, name: label.name, colorHex: label.colorHex)
        }
        let stickies = stickyEntities(dto.stickies)
        let state = BoardState(
            board: board, columns: columns, cards: cards,
            stickies: stickies, shapes: shapeEntities(dto.shapes ?? []),
            images: imageEntities(dto.images ?? []),
            connectors: connectorEntities(dto.connectors ?? [], stickyIDs: Set(stickies.map(\.id)),
                                          into: &recoveries),
            texts: textEntities(dto.texts ?? []),
            labels: labels,
            settings: settingsEntity(dto.settings)
        )
        return (state, recoveries)
    }

    /// State-only convenience for callers that **deliberately discard** the recovery notes — tests
    /// and round-trip checks, never a production decode. The name spells out the footgun: a
    /// production caller using this would silently skip the recovery logging that `decode(_:)` →
    /// `BoardRepository.decodeSnapshot` exists to provide. Every production path calls `decode(_:)`.
    static func decodeIgnoringRecoveries(_ dto: BoardSnapshotDTO) -> BoardState {
        decode(dto).state
    }

    private static func cardEntity(_ card: CardDTO, into recoveries: inout [SnapshotRecovery]) -> Card {
        Card(
            id: card.id,
            columnID: card.columnID,
            title: card.title,
            markdownContent: card.markdownContent,
            schedule: mapSchedule(card.schedule, cardID: card.id, into: &recoveries),
            labels: card.labels.map { label in
                CardLabel(id: label.id, name: label.name, colorHex: label.colorHex)
            },
            assignee: card.assignee,
            prURL: card.prURL,
            completedAt: card.completedAt,
            createdAt: card.createdAt ?? .distantPast,
            sortIndex: card.sortIndex
        )
    }

    private static func stickyEntities(_ dtos: [StickyDTO]) -> [Sticky] {
        dtos.enumerated().map { index, sticky in
            Sticky(
                id: sticky.id,
                cardID: sticky.cardID,
                linkedCardID: sticky.linkedCardID,
                content: sticky.content,
                position: CanvasPosition(x: sticky.positionX, y: sticky.positionY),
                size: StickySize(width: sticky.width, height: sticky.height),
                style: StickyTextStyle(
                    // A missing value falls back to the default; a legacy "auto" value is coerced
                    // to the default inside StickyTextStyle.init (the entity owns that rule).
                    colorHex: sticky.textColorHex ?? StickyTextStyle.defaultColorHex,
                    fontSize: sticky.fontSize ?? StickyTextStyle.defaultFontSize
                ),
                fillColorHex: sticky.fillColorHex,
                sortIndex: sticky.sortIndex ?? index,
                labelIDs: sticky.labelIDs ?? []
            )
        }
    }

    private static func shapeEntities(_ dtos: [ShapeDTO]) -> [CanvasShape] {
        dtos.enumerated().map { index, shape in
            CanvasShape(
                id: shape.id,
                cardID: shape.cardID,
                kind: shape.kind,
                topology: shape.topology.flatMap(ShapeTopology.init(rawValue:))
                    ?? .inferred(fromKind: shape.kind),
                position: CanvasPosition(x: shape.positionX, y: shape.positionY),
                size: ShapeSize(width: shape.width, height: shape.height),
                style: CanvasShapeStyle(
                    strokeColorHex: shape.strokeColorHex ?? CanvasShapeStyle.defaultStrokeColorHex,
                    // A persisted shape carries an explicit `hasFill` flag so "no fill" survives a
                    // round-trip: `fillColorHex == nil` could otherwise mean either "no fill" or
                    // "field absent in an old snapshot". `hasFill == false` ⇒ stroke-only.
                    fillColorHex: (shape.hasFill ?? (shape.fillColorHex != nil)) ? shape.fillColorHex : nil,
                    strokeWidth: shape.strokeWidth ?? CanvasShapeStyle.defaultStrokeWidth
                ),
                lineRising: shape.lineRising ?? false,
                sortIndex: shape.sortIndex ?? index
            )
        }
    }

    private static func imageEntities(_ dtos: [ImageDTO]) -> [CanvasImage] {
        dtos.enumerated().map { index, image in
            // A pre-aspectRatio snapshot falls back to the stored box ratio (it was un-distorted
            // when written, so width/height carry the true shape). Re-clamped via `ImageSize`.
            let ratio = image.aspectRatio ?? (image.height > 0 ? image.width / image.height : 1)
            return CanvasImage(
                id: image.id,
                cardID: image.cardID,
                assetID: image.assetID,
                position: CanvasPosition(x: image.positionX, y: image.positionY),
                size: ImageSize(width: image.width, height: image.height),
                aspectRatio: ratio,
                sortIndex: image.sortIndex ?? index
            )
        }
    }

    static func toDTO(_ state: BoardState) -> BoardSnapshotDTO {
        let boardDTO = BoardDTO(id: state.board.id, title: state.board.title)
        let columnDTOs = state.columns.map { col in
            ColumnDTO(
                id: col.id,
                boardID: col.boardID,
                title: col.title,
                sortIndex: col.sortIndex,
                isCompletionColumn: col.isCompletionColumn,
                headerColorHex: col.headerColorHex,
                headerTextColorHex: col.headerTextColorHex,
                bodyColorHex: col.bodyColorHex,
                headerBorderColorHex: col.headerBorderColorHex,
                bodyBorderColorHex: col.bodyBorderColorHex,
                indicatorColorHex: col.indicatorColorHex
            )
        }
        let labelDTOs = state.labels.map { label in
            StickyLabelDTO(id: label.id, name: label.name, colorHex: label.colorHex)
        }
        return BoardSnapshotDTO(
            board: boardDTO, columns: columnDTOs, cards: state.cards.map(cardDTO),
            stickies: state.stickies.map(stickyDTO), shapes: state.shapes.map(shapeDTO),
            images: state.images.map(imageDTO),
            connectors: state.connectors.map(connectorDTO),
            texts: state.texts.map(textDTO), labels: labelDTOs,
            settings: settingsDTO(state.settings)
        )
    }

    private static func cardDTO(_ card: Card) -> CardDTO {
        CardDTO(
            id: card.id,
            columnID: card.columnID,
            title: card.title,
            markdownContent: card.markdownContent,
            status: nil, // Status is derived from the column now; no longer persisted on the card.
            schedule: scheduleDTO(card.schedule),
            labels: card.labels.map { label in
                CardLabelDTO(id: label.id, name: label.name, colorHex: label.colorHex)
            },
            assignee: card.assignee,
            prURL: card.prURL,
            completedAt: card.completedAt,
            createdAt: card.createdAt,
            sortIndex: card.sortIndex
        )
    }

    private static func stickyDTO(_ sticky: Sticky) -> StickyDTO {
        StickyDTO(
            id: sticky.id,
            cardID: sticky.cardID,
            linkedCardID: sticky.linkedCardID,
            content: sticky.content,
            positionX: sticky.position.x,
            positionY: sticky.position.y,
            width: sticky.size.width,
            height: sticky.size.height,
            textColorHex: sticky.style.colorHex,
            fontSize: sticky.style.fontSize,
            fillColorHex: sticky.fillColorHex,
            sortIndex: sticky.sortIndex,
            labelIDs: sticky.labelIDs
        )
    }

    private static func shapeDTO(_ shape: CanvasShape) -> ShapeDTO {
        ShapeDTO(
            id: shape.id,
            cardID: shape.cardID,
            kind: shape.kind,
            topology: shape.topology.rawValue,
            positionX: shape.position.x,
            positionY: shape.position.y,
            width: shape.size.width,
            height: shape.size.height,
            strokeColorHex: shape.style.strokeColorHex,
            strokeWidth: shape.style.strokeWidth,
            // Persist the fill colour plus an explicit presence flag so "no fill" is
            // distinguishable from "field absent" on the next decode.
            fillColorHex: shape.style.fillColorHex,
            hasFill: shape.style.fillColorHex != nil,
            lineRising: shape.lineRising,
            sortIndex: shape.sortIndex
        )
    }

}

// MARK: - Image & schedule mapping

private extension BoardSnapshotMapper {

    static func imageDTO(_ image: CanvasImage) -> ImageDTO {
        ImageDTO(
            id: image.id,
            cardID: image.cardID,
            assetID: image.assetID,
            positionX: image.position.x,
            positionY: image.position.y,
            width: image.size.width,
            height: image.size.height,
            aspectRatio: image.aspectRatio,
            sortIndex: image.sortIndex
        )
    }

    /// Maps a persisted schedule, **recording a recovery** whenever it must be discarded: an unknown
    /// `kind`, or a known kind missing its required date(s). An *absent* schedule (`dto == nil`) is a
    /// legitimate "no schedule", not a recovery. Each drop is a latent write — the next save persists
    /// the now-empty schedule — so it must be observable (`arch-repository.md` → "Latent write-back").
    static func mapSchedule(_ dto: CardScheduleDTO?, cardID: UUID,
                            into recoveries: inout [SnapshotRecovery]) -> CardSchedule? {
        guard let dto else { return nil }
        switch dto.kind {
        case ScheduleKind.deadline:
            guard let date = dto.date else {
                recoveries.append(.scheduleDropped(cardID: cardID, reason: "deadline missing date",
                                                   rawKind: dto.kind))
                return nil
            }
            return .deadline(date)
        case ScheduleKind.period:
            guard let start = dto.startDate, let end = dto.endDate else {
                recoveries.append(.scheduleDropped(cardID: cardID, reason: "period missing start/end",
                                                   rawKind: dto.kind))
                return nil
            }
            return .period(start: start, end: end)
        default:
            recoveries.append(.scheduleDropped(cardID: cardID, reason: "unknown kind", rawKind: dto.kind))
            return nil
        }
    }

    static func scheduleDTO(_ schedule: CardSchedule?) -> CardScheduleDTO? {
        guard let schedule else { return nil }
        switch schedule {
        case .deadline(let date):
            return CardScheduleDTO(kind: ScheduleKind.deadline, date: date, startDate: nil, endDate: nil)
        case .period(let start, let end):
            return CardScheduleDTO(kind: ScheduleKind.period, date: nil, startDate: start, endDate: end)
        }
    }
}

