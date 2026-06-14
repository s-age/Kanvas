import Foundation

struct BoardResponseMapper: Sendable {
    func toBoardResponse(_ state: BoardState) -> BoardResponse {
        BoardResponse(
            board: BoardSummary(id: state.board.id, title: state.board.title),
            columns: state.columns
                .sorted { $0.sortIndex < $1.sortIndex }
                .map { column in
                    // Card display order follows the board's sort policy (`manual` = drag order).
                    let cardsInColumn = state.cards.filter { $0.columnID == column.id }
                    // Status is derived from the column, so it is identical for every card here —
                    // hoist it out of the per-card map (mirrors how `stickyResponses` hoists
                    // `labelResponses`) to avoid an O(cards × columns) rescan.
                    let columnStatus = state.status(forColumn: column.id)
                    let cards = state.settings.board.cardSortPolicy
                        .ordered(cardsInColumn)
                        .map { card in
                            CardSummary(
                                id: card.id,
                                title: card.title,
                                status: CardStatusResponse(columnStatus),
                                hasSchedule: card.schedule != nil,
                                labelCount: card.labels.count
                            )
                        }
                    return ColumnResponse(
                        id: column.id,
                        title: column.title,
                        sortIndex: column.sortIndex,
                        isCompletionColumn: column.isCompletionColumn,
                        headerColorHex: column.headerColorHex,
                        headerTextColorHex: column.headerTextColorHex,
                        bodyColorHex: column.bodyColorHex,
                        headerBorderColorHex: column.headerBorderColorHex,
                        bodyBorderColorHex: column.bodyBorderColorHex,
                        indicatorColorHex: column.indicatorColorHex,
                        cards: cards
                    )
                },
            labels: state.labels.map {
                StickyLabelResponse(id: $0.id, name: $0.name, colorHex: $0.colorHex)
            },
            settings: settingsResponse(state.settings)
        )
    }

    func toCardDetailResponse(cardID: Card.ID, from state: BoardState) -> CardDetailResponse? {
        guard let card = state.cards.first(where: { $0.id == cardID }) else { return nil }
        return CardDetailResponse(
            id: card.id,
            title: card.title,
            markdownContent: card.markdownContent,
            status: CardStatusResponse(state.status(forColumn: card.columnID)),
            columnTitle: state.columnTitle(forColumn: card.columnID),
            schedule: mapSchedule(card.schedule),
            labels: card.labels.map { LabelResponse(id: $0.id, name: $0.name, colorHex: $0.colorHex) },
            assignee: card.assignee,
            prURL: card.prURL,
            completedAt: card.completedAt,
            stickies: stickyResponses(cardID: cardID, from: state),
            shapes: shapeResponses(cardID: cardID, from: state),
            images: imageResponses(cardID: cardID, from: state),
            texts: textResponses(cardID: cardID, from: state),
            connectors: connectorResponses(cardID: cardID, from: state)
        )
    }

    private func textResponses(cardID: Card.ID, from state: BoardState) -> [TextResponse] {
        state.texts
            .filter { $0.cardID == cardID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { text in
                TextResponse(
                    id: text.id,
                    content: text.content,
                    positionX: text.position.x,
                    positionY: text.position.y,
                    width: text.size.width,
                    height: text.size.height,
                    minWidth: TextSize.minWidth,
                    minHeight: TextSize.minHeight,
                    maxWidth: TextSize.maxWidth,
                    maxHeight: TextSize.maxHeight,
                    textColorHex: text.style.colorHex,
                    fontSize: text.style.fontSize,
                    minFontSize: CanvasTextStyle.minFontSize,
                    maxFontSize: CanvasTextStyle.maxFontSize,
                    sortIndex: text.sortIndex
                )
            }
    }

    private func stickyResponses(cardID: Card.ID, from state: BoardState) -> [StickyResponse] {
        // Map the registry to Responses once; per-sticky resolution is then a Set membership test
        // (preserving registry order), instead of an O(labels × labelIDs) scan per sticky.
        let labelResponses = state.labels.map {
            StickyLabelResponse(id: $0.id, name: $0.name, colorHex: $0.colorHex)
        }
        return state.stickies
            .filter { $0.cardID == cardID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { sticky in
                let linkedTitle = sticky.linkedCardID.flatMap { lid in
                    state.cards.first { $0.id == lid }?.title
                }
                // Resolve tagged ids against the registry, preserving registry order; drop ids
                // that no longer resolve to a label.
                let assigned = Set(sticky.labelIDs)
                let stickyLabels = labelResponses.filter { assigned.contains($0.id) }
                return StickyResponse(
                    id: sticky.id,
                    content: sticky.content,
                    isTask: sticky.isTask,
                    linkedCardTitle: linkedTitle,
                    positionX: sticky.position.x,
                    positionY: sticky.position.y,
                    width: sticky.size.width,
                    height: sticky.size.height,
                    minWidth: StickySize.minWidth,
                    minHeight: StickySize.minHeight,
                    maxWidth: StickySize.maxWidth,
                    maxHeight: StickySize.maxHeight,
                    textColorHex: sticky.style.colorHex,
                    fontSize: sticky.style.fontSize,
                    fillColorHex: sticky.fillColorHex,
                    sortIndex: sticky.sortIndex,
                    labels: stickyLabels
                )
            }
    }

    private func shapeResponses(cardID: Card.ID, from state: BoardState) -> [ShapeResponse] {
        state.shapes
            .filter { $0.cardID == cardID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { shape in
                ShapeResponse(
                    id: shape.id,
                    kind: shape.kind,
                    topology: ShapeTopologyResponse(shape.topology),
                    positionX: shape.position.x,
                    positionY: shape.position.y,
                    width: shape.size.width,
                    height: shape.size.height,
                    minWidth: ShapeSize.minWidth,
                    minHeight: ShapeSize.minHeight,
                    maxWidth: ShapeSize.maxWidth,
                    maxHeight: ShapeSize.maxHeight,
                    strokeColorHex: shape.style.strokeColorHex,
                    strokeWidth: shape.style.strokeWidth,
                    minStrokeWidth: CanvasShapeStyle.minStrokeWidth,
                    maxStrokeWidth: CanvasShapeStyle.maxStrokeWidth,
                    fillColorHex: shape.style.fillColorHex,
                    lineRising: shape.lineRising,
                    sortIndex: shape.sortIndex
                )
            }
    }

    private func imageResponses(cardID: Card.ID, from state: BoardState) -> [ImageResponse] {
        state.images
            .filter { $0.cardID == cardID }
            .sorted { $0.sortIndex < $1.sortIndex }
            .map { image in
                ImageResponse(
                    id: image.id,
                    assetID: image.assetID,
                    positionX: image.position.x,
                    positionY: image.position.y,
                    width: image.size.width,
                    height: image.size.height,
                    minWidth: ImageSize.minWidth,
                    minHeight: ImageSize.minHeight,
                    maxWidth: ImageSize.maxWidth,
                    maxHeight: ImageSize.maxHeight,
                    aspectRatio: image.aspectRatio,
                    sortIndex: image.sortIndex
                )
            }
    }

    private func connectorResponses(cardID: Card.ID, from state: BoardState) -> [ConnectorResponse] {
        state.connectors
            .filter { $0.cardID == cardID }
            .map { connector in
                ConnectorResponse(
                    id: connector.id,
                    sourceStickyID: connector.sourceStickyID,
                    sourceEdge: CanvasEdgeResponse(connector.sourceEdge),
                    targetStickyID: connector.targetStickyID,
                    targetEdge: CanvasEdgeResponse(connector.targetEdge),
                    cap: ConnectorCapResponse(connector.style.cap),
                    routing: ConnectorRoutingResponse(connector.style.routing),
                    strokeColorHex: connector.style.strokeColorHex,
                    strokeWidth: connector.style.strokeWidth,
                    minStrokeWidth: ConnectorStyle.minStrokeWidth,
                    maxStrokeWidth: ConnectorStyle.maxStrokeWidth,
                    waypointOffsetX: connector.waypointOffset?.dx,
                    waypointOffsetY: connector.waypointOffset?.dy
                )
            }
    }

    private func mapSchedule(_ schedule: CardSchedule?) -> ScheduleResponse? {
        guard let schedule else { return nil }
        switch schedule {
        case .deadline(let date):
            return .deadline(date)
        case .period(let start, let end):
            return .period(start: start, end: end)
        }
    }
}

// MARK: - Combined + list responses

extension BoardResponseMapper {

    /// Builds the combined post-mutation response: the board plus, when `affectedCardID` resolves
    /// to a card, that card's refreshed detail (so the caller skips a redundant card-detail disk
    /// read — ticket 1DCBF9C9). A `nil` (or no-longer-present) `affectedCardID` yields
    /// `cardDetail == nil`, and the caller falls back to a fresh load.
    func toBoardMutation(_ state: BoardState, affectedCardID: Card.ID?) -> BoardMutationResponse {
        BoardMutationResponse(
            board: toBoardResponse(state),
            cardDetail: affectedCardID.flatMap { toCardDetailResponse(cardID: $0, from: state) }
        )
    }

    func toBoardListResponse(boards: [Board], activeBoardID: UUID?) -> BoardListResponse {
        BoardListResponse(
            boards: boards.map { BoardSummary(id: $0.id, title: $0.title) },
            activeBoardID: activeBoardID
        )
    }
}

// MARK: - Settings mapping

extension BoardResponseMapper {

    func settingsResponse(_ settings: BoardSettings) -> BoardSettingsResponse {
        BoardSettingsResponse(
            global: GlobalSettingsResponse(
                backgroundColorHex: settings.global.backgroundColorHex,
                textColorHex: settings.global.textColorHex,
                colorPalette: settings.global.colorPalette.map {
                    PaletteColorResponse(id: $0.id, colorHex: $0.colorHex, label: $0.label)
                }
            ),
            board: BoardTabSettingsResponse(
                cardSortPolicy: CardSortPolicyResponse(settings.board.cardSortPolicy),
                autoCompleteOnMove: settings.board.autoCompleteOnMove,
                cardBackgroundColorHex: settings.board.cardBackgroundColorHex,
                cardTextColorHex: settings.board.cardTextColorHex,
                cardBorderColorHex: settings.board.cardBorderColorHex,
                textColorHex: settings.board.textColorHex,
                newCardPosition: NewCardPositionResponse(settings.board.newCardPosition)
            ),
            canvas: CanvasSettingsResponse(settings.canvas),
            markdown: MarkdownSettingsResponse(settings.markdown)
        )
    }
}
