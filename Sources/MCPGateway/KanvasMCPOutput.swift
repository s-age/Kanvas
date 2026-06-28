import Foundation

/// Model-facing JSON shapes for the MCP gateway and the encoder that emits them.
///
/// These are deliberately **separate** from the UseCase `Response` types: the gateway maps each
/// `Response` into one of these `Encodable` DTOs so the JSON a model sees is small, stable, and
/// documented here — and so the internal `Response` types need not become `Codable`. Keeping the
/// shapes here (not in `Tools/`) lets the JSON contract live next to the gateway that produces it.
enum MCPJSON {
    /// Pretty-printed, key-sorted JSON so a model gets stable, diff-friendly output.
    static func encode(_ value: some Encodable) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}

// MARK: - Board (Kanban top level)

struct BoardOut: Encodable {
    let id: UUID
    let title: String
    let columns: [ColumnOut]

    init(_ response: BoardResponse) {
        id = response.board.id
        title = response.board.title
        columns = response.columns.map(ColumnOut.init)
    }
}

struct ColumnOut: Encodable {
    let id: UUID
    let title: String
    let sortIndex: Int
    let isCompletionColumn: Bool
    let cards: [CardOut]

    init(_ response: ColumnResponse) {
        id = response.id
        title = response.title
        sortIndex = response.sortIndex
        isCompletionColumn = response.isCompletionColumn
        cards = response.cards.map(CardOut.init)
    }
}

struct CardOut: Encodable {
    let id: UUID
    let title: String
    let status: String
    let hasSchedule: Bool
    let labelCount: Int

    init(_ summary: CardSummary) {
        id = summary.id
        title = summary.title
        status = summary.status.rawValue
        hasSchedule = summary.hasSchedule
        labelCount = summary.labelCount
    }
}

struct BoardListOut: Encodable {
    let activeBoardID: UUID?
    let boards: [BoardRefOut]

    init(_ response: BoardListResponse) {
        activeBoardID = response.activeBoardID
        boards = response.boards.map { BoardRefOut(id: $0.id, title: $0.title) }
    }
}

struct BoardRefOut: Encodable {
    let id: UUID
    let title: String
}

// MARK: - Canvas (a card's stickies) + Markdown

/// A card's canvas: stickies and the connectors linking them (the writable MCP scope). Shapes and
/// images are reported as counts only — their own tools come later.
struct CardDetailOut: Encodable {
    let id: UUID
    let title: String
    let markdownContent: String
    let status: String
    let assignee: String?
    let prURL: String?
    let stickies: [StickyOut]
    let texts: [TextOut]
    let connectors: [ConnectorOut]
    let shapeCount: Int
    let imageCount: Int

    init(_ response: CardDetailResponse) {
        id = response.id
        title = response.title
        markdownContent = response.markdownContent
        status = response.status.rawValue
        assignee = response.assignee
        prURL = response.prURL
        stickies = response.stickies.map(StickyOut.init)
        texts = response.texts.map(TextOut.init)
        connectors = response.connectors.map(ConnectorOut.init)
        shapeCount = response.shapes.count
        imageCount = response.images.count
    }
}

/// A free-text canvas object (background/border-less text). `x`/`y` are its centre; text wraps to
/// `width` and is clipped at `height`.
struct TextOut: Encodable {
    let id: UUID
    let content: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let textColorHex: String
    let fontSize: Double
    let sortIndex: Int

    init(_ response: TextResponse) {
        id = response.id
        content = response.content
        x = response.positionX
        y = response.positionY
        width = response.width
        height = response.height
        textColorHex = response.textColorHex
        fontSize = response.fontSize
        sortIndex = response.sortIndex
    }
}

/// An arrow/line linking two stickies. Endpoints are sticky ids + the edge ("top" / "bottom" /
/// "left" / "right") the line leaves from / arrives at; connectors carry no geometry of their own.
struct ConnectorOut: Encodable {
    let id: UUID
    let sourceStickyID: UUID
    let sourceEdge: String
    let targetStickyID: UUID
    let targetEdge: String
    let cap: String
    let routing: String
    /// `nil` (key omitted in JSON via the synthesized `encodeIfPresent`) = the stroke colour is
    /// **unset** and rendered adaptively (`#333`/`#ddd` by the live background); a present hex is an
    /// explicit pick honoured verbatim — including pure `000000`. Mirrors `ConnectorStyle`.
    let strokeColorHex: String?
    let strokeWidth: Double

    init(_ response: ConnectorResponse) {
        id = response.id
        sourceStickyID = response.sourceStickyID
        sourceEdge = response.sourceEdge.rawValue
        targetStickyID = response.targetStickyID
        targetEdge = response.targetEdge.rawValue
        cap = response.cap.rawValue
        routing = response.routing.rawValue
        strokeColorHex = response.strokeColorHex
        strokeWidth = response.strokeWidth
    }
}

struct StickyOut: Encodable {
    let id: UUID
    let content: String
    /// `true` when this sticky is linked to a sub-card in the Kanban (a "task" sticky).
    let isTask: Bool
    let linkedCardTitle: String?
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    let fillColorHex: String?
    let textColorHex: String
    let fontSize: Double
    let sortIndex: Int

    init(_ response: StickyResponse) {
        id = response.id
        content = response.content
        isTask = response.isTask
        linkedCardTitle = response.linkedCardTitle
        x = response.positionX
        y = response.positionY
        width = response.width
        height = response.height
        fillColorHex = response.fillColorHex
        textColorHex = response.textColorHex
        fontSize = response.fontSize
        sortIndex = response.sortIndex
    }
}

/// Result of a write that adds an element — echoes the refreshed view plus the new element's id so
/// a model can address it immediately without diffing.
struct CardCreatedOut: Encodable {
    let newCardID: UUID
    let board: BoardOut
}

// MARK: - Minimal write echoes (token-light)

/// Token-light echo for a single-card write (`board_card_edit` / `board_card_move`): just the
/// affected card plus the column it now sits in — **not** the whole refreshed board. A title-only
/// edit would otherwise re-emit every card summary on the active board (hundreds on a busy board, ~22k
/// tokens here), even though only one card changed. The model addresses the card by id and re-reads
/// the full board with `board_get` only when it actually needs the wider picture. Mirrors the
/// already-light `board_card_set_pr_url` → `CardPRURLOut` path.
struct CardEchoOut: Encodable {
    let columnID: UUID
    let id: UUID
    let title: String
    let status: String
    let hasSchedule: Bool
    let labelCount: Int

    init(_ summary: CardSummary, columnID: UUID) {
        self.columnID = columnID
        id = summary.id
        title = summary.title
        status = summary.status.rawValue
        hasSchedule = summary.hasSchedule
        labelCount = summary.labelCount
    }
}

/// Echo for a delete (`board_card_delete`): just the id that was removed, so the model confirms the
/// target without the whole refreshed board (the deleted card is gone; listing the survivors would be
/// the same blow-up the other echoes avoid).
struct DeletedOut: Encodable {
    let deletedID: UUID
}

/// Token-light echo for a column write (`board_column_add` / `_rename` / `_delete` /
/// `_appearance_edit`): the board's columns with their metadata and per-column card *counts* — but
/// not the card summaries themselves. Column ops never touch card contents, and a board can carry
/// hundreds of cards, so echoing the cards would reintroduce the blow-up these echoes exist to kill.
/// Listing the columns also surfaces `board_column_add`'s new column id, which the use case otherwise
/// only returns buried in the full board.
struct BoardColumnsOut: Encodable {
    let id: UUID
    let title: String
    let columns: [ColumnMetaOut]

    init(_ response: BoardResponse) {
        id = response.board.id
        title = response.board.title
        columns = response.columns.map(ColumnMetaOut.init)
    }
}

/// One column without its card summaries — the per-column shape inside `BoardColumnsOut`. Carries the
/// colour fields (so an appearance edit echoes the resolved result) plus a bare `cardCount`.
struct ColumnMetaOut: Encodable {
    let id: UUID
    let title: String
    let sortIndex: Int
    let isCompletionColumn: Bool
    let headerColorHex: String?
    let headerTextColorHex: String?
    let bodyColorHex: String?
    let headerBorderColorHex: String?
    let bodyBorderColorHex: String?
    let indicatorColorHex: String?
    let cardCount: Int

    init(_ response: ColumnResponse) {
        id = response.id
        title = response.title
        sortIndex = response.sortIndex
        isCompletionColumn = response.isCompletionColumn
        headerColorHex = response.headerColorHex
        headerTextColorHex = response.headerTextColorHex
        bodyColorHex = response.bodyColorHex
        headerBorderColorHex = response.headerBorderColorHex
        bodyBorderColorHex = response.bodyBorderColorHex
        indicatorColorHex = response.indicatorColorHex
        cardCount = response.cards.count
    }
}

struct MarkdownOut: Encodable {
    let cardID: UUID
    let title: String
    let markdownContent: String
}

/// Minimal echo for the dedicated PR-URL setter — just the card's id, title, and (possibly cleared)
/// PR URL. Deliberately omits stickies/markdown so the token-light setter stays light on the way out
/// too. `prURL` is `nil` when the link was cleared or never set.
struct CardPRURLOut: Encodable {
    let cardID: UUID
    let title: String
    let prURL: String?
}
