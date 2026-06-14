import Foundation

/// Public entry the `KanvasMCP` executable calls to obtain a gateway. Keeps `Container` internal —
/// the executable never names the composition root, only this and `KanvasMCPGateway`.
public enum KanvasMCP {
    public static func makeGateway() -> KanvasMCPGateway {
        Container.shared.makeMCPGateway()
    }
}

/// The MCP server's **single public entry point** into KanvasCore. It bundles the UseCase-layer
/// operations a model needs for Board / Canvas / Markdown and exposes them as primitive-in,
/// JSON-string-out methods — so the `KanvasMCP` executable drives the exact same product code as
/// the app, and the 60 internal use cases / Request / Response types stay internal (this gateway is
/// the only `public` surface they reach).
///
/// Layer-wise this is a sibling of Presentation: it consumes UseCase `Request`/`Response` types and
/// never touches Domain entities. Construction is internal — only `Container.makeMCPGateway()`
/// builds it; the MCP target obtains an instance from there.
public final class KanvasMCPGateway: Sendable {
    let loadActiveBoardUseCase: LoadActiveBoardUseCase
    let loadBoardByIDUseCase: LoadBoardByIDUseCase
    let listBoardsUseCase: ListBoardsUseCase
    let addCardUseCase: AddCardUseCase
    let editCardUseCase: EditCardUseCase
    let moveCardUseCase: MoveCardUseCase
    let deleteCardUseCase: DeleteCardUseCase
    let addColumnUseCase: AddColumnUseCase
    let renameColumnUseCase: RenameColumnUseCase
    let deleteColumnUseCase: DeleteColumnUseCase
    let editBoardSettingsUseCase: EditBoardSettingsUseCase
    let editColumnAppearanceUseCase: EditColumnAppearanceUseCase
    let loadCardDetailUseCase: any LoadCardDetailUseCase
    let addStickyUseCase: AddStickyUseCase
    let editStickyUseCase: EditStickyUseCase
    let moveStickyUseCase: MoveStickyUseCase
    let setStickyFrameUseCase: SetStickyFrameUseCase
    let deleteStickyUseCase: DeleteStickyUseCase
    let promoteStickyUseCase: PromoteStickyUseCase
    let demoteStickyUseCase: DemoteStickyUseCase
    let addTextUseCase: AddTextUseCase
    let editTextUseCase: EditTextUseCase
    let moveTextUseCase: MoveTextUseCase
    let resizeTextUseCase: ResizeTextUseCase
    let setTextColorUseCase: SetTextColorUseCase
    let setTextFontSizeUseCase: SetTextFontSizeUseCase
    let deleteTextUseCase: DeleteTextUseCase
    let addConnectorUseCase: AddConnectorUseCase
    let deleteConnectorUseCase: DeleteConnectorUseCase
    let setConnectorStyleUseCase: SetConnectorStyleUseCase
    let reconnectConnectorUseCase: ReconnectConnectorUseCase
    let saveImageAssetUseCase: SaveImageAssetUseCase
    let deleteMarkdownImageUseCase: DeleteMarkdownImageUseCase

    init(
        loadActiveBoard: LoadActiveBoardUseCase,
        loadBoardByID: LoadBoardByIDUseCase,
        listBoards: ListBoardsUseCase,
        addCard: AddCardUseCase,
        editCard: EditCardUseCase,
        moveCard: MoveCardUseCase,
        deleteCard: DeleteCardUseCase,
        addColumn: AddColumnUseCase,
        renameColumn: RenameColumnUseCase,
        deleteColumn: DeleteColumnUseCase,
        editBoardSettings: EditBoardSettingsUseCase,
        editColumnAppearance: EditColumnAppearanceUseCase,
        loadCardDetail: any LoadCardDetailUseCase,
        addSticky: AddStickyUseCase,
        editSticky: EditStickyUseCase,
        moveSticky: MoveStickyUseCase,
        setStickyFrame: SetStickyFrameUseCase,
        deleteSticky: DeleteStickyUseCase,
        promoteSticky: PromoteStickyUseCase,
        demoteSticky: DemoteStickyUseCase,
        addText: AddTextUseCase,
        editText: EditTextUseCase,
        moveText: MoveTextUseCase,
        resizeText: ResizeTextUseCase,
        setTextColor: SetTextColorUseCase,
        setTextFontSize: SetTextFontSizeUseCase,
        deleteText: DeleteTextUseCase,
        addConnector: AddConnectorUseCase,
        deleteConnector: DeleteConnectorUseCase,
        setConnectorStyle: SetConnectorStyleUseCase,
        reconnectConnector: ReconnectConnectorUseCase,
        saveImageAsset: SaveImageAssetUseCase,
        deleteMarkdownImage: DeleteMarkdownImageUseCase
    ) {
        loadActiveBoardUseCase = loadActiveBoard
        loadBoardByIDUseCase = loadBoardByID
        listBoardsUseCase = listBoards
        addCardUseCase = addCard
        editCardUseCase = editCard
        moveCardUseCase = moveCard
        deleteCardUseCase = deleteCard
        addColumnUseCase = addColumn
        renameColumnUseCase = renameColumn
        deleteColumnUseCase = deleteColumn
        editBoardSettingsUseCase = editBoardSettings
        editColumnAppearanceUseCase = editColumnAppearance
        loadCardDetailUseCase = loadCardDetail
        addStickyUseCase = addSticky
        editStickyUseCase = editSticky
        moveStickyUseCase = moveSticky
        setStickyFrameUseCase = setStickyFrame
        deleteStickyUseCase = deleteSticky
        promoteStickyUseCase = promoteSticky
        demoteStickyUseCase = demoteSticky
        addTextUseCase = addText
        editTextUseCase = editText
        moveTextUseCase = moveText
        resizeTextUseCase = resizeText
        setTextColorUseCase = setTextColor
        setTextFontSizeUseCase = setTextFontSize
        deleteTextUseCase = deleteText
        addConnectorUseCase = addConnector
        deleteConnectorUseCase = deleteConnector
        setConnectorStyleUseCase = setConnectorStyle
        reconnectConnectorUseCase = reconnectConnector
        saveImageAssetUseCase = saveImageAsset
        deleteMarkdownImageUseCase = deleteMarkdownImage
    }

    // MARK: - Shared helpers (used by the Board/Canvas/Markdown extensions)

    func uuid(_ value: String, _ field: String) throws -> UUID {
        guard let id = UUID(uuidString: value) else {
            throw KanvasMCPError.badUUID(field: field, value: value)
        }
        return id
    }

    /// Pins an omittable tool argument onto a request's keep/set double-optional: nil (argument
    /// omitted) → nil (keep), provided value → .some(.some(value)). The explicit two-level wrap
    /// exists because handing a `T?` straight to a `T??` parameter makes the compiler *promote*
    /// it — wrapping the whole optional in `.some` — so an omitted argument (keep) would silently
    /// become `.some(nil)` (clear). Static and pure so the contract is pinned by unit tests, not
    /// just this comment.
    static func requestEdit<T>(_ argument: T?) -> T?? {
        argument.map { Optional($0) }
    }

    /// Parses + pins the `schedule` tool argument in one step: nil (omitted) → nil (keep),
    /// "none" → .some(nil) (clear), date string(s) → .some(.some(schedule)). The promotion is
    /// unambiguous here because `scheduleValue` already returns an Optional.
    static func scheduleEdit(_ argument: String?) throws -> ScheduleInput?? {
        try argument.map { try scheduleValue($0) }
    }

    /// Parses the `schedule` tool argument: "none" clears, "YYYY-MM-DD" sets a deadline,
    /// "YYYY-MM-DD/YYYY-MM-DD" sets a period. Dates resolve to local midnight, matching what the
    /// app's date pickers produce for a picked day. Static (no gateway state) so the format
    /// contract is unit-testable without composing the 18-use-case gateway.
    static func scheduleValue(_ value: String) throws -> ScheduleInput? {
        if value == "none" { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        switch parts.count {
        case 1: return .deadline(try day(parts[0], whole: value))
        case 2: return .period(start: try day(parts[0], whole: value), end: try day(parts[1], whole: value))
        default: throw KanvasMCPError.badSchedule(value: value)
        }
    }

    private static func day(_ raw: Substring, whole: String) throws -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: String(raw)) else {
            throw KanvasMCPError.badSchedule(value: whole)
        }
        return date
    }

}

/// A sticky's canvas frame (centre + size), bundled so the gateway's add / set-frame methods stay
/// within the parameter-count budget. `x`/`y` are the sticky's centre in canvas coordinates.
public struct StickyFrame: Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

/// The fields `board_column_appearance_edit` may change on one column. Each colour is `nil` when its
/// tool key was omitted (keep), `""` to clear to the system default, or a hex string to set;
/// `isCompletionColumn` is `nil` to keep or a bool to set. Bundled — like `StickyFrame` — to keep
/// the gateway method within the parameter-count budget. The wire sentinel is mapped to the Request's
/// double-optional keep/clear/set intent by `KanvasMCPGateway.keepClearSet`; the actual overlay
/// against the live column lives in the domain (`BoardManagementService.editColumnAppearance`'s mutate
/// block, applied inside the store lock), so the resolution is atomic with the read (ticket 620B3601).
public struct ColumnAppearanceEdit: Sendable {
    public let headerColorHex: String?
    public let headerTextColorHex: String?
    public let bodyColorHex: String?
    public let headerBorderColorHex: String?
    public let bodyBorderColorHex: String?
    public let indicatorColorHex: String?
    public let isCompletionColumn: Bool?

    public init(
        headerColorHex: String?,
        headerTextColorHex: String?,
        bodyColorHex: String?,
        headerBorderColorHex: String?,
        bodyBorderColorHex: String?,
        indicatorColorHex: String?,
        isCompletionColumn: Bool?
    ) {
        self.headerColorHex = headerColorHex
        self.headerTextColorHex = headerTextColorHex
        self.bodyColorHex = bodyColorHex
        self.headerBorderColorHex = headerBorderColorHex
        self.bodyBorderColorHex = bodyBorderColorHex
        self.indicatorColorHex = indicatorColorHex
        self.isCompletionColumn = isCompletionColumn
    }
}

/// The style fields `canvas_text_edit` may change alongside the content; nil means "keep". Bundled —
/// like `StickyFrame` — to keep the gateway method within the parameter-count budget.
public struct TextStyleEdit: Sendable {
    public let colorHex: String?
    public let fontSize: Double?

    public init(colorHex: String?, fontSize: Double?) {
        self.colorHex = colorHex
        self.fontSize = fontSize
    }
}

/// A connector's two endpoints as the model supplies them: source sticky + edge, target edge, and
/// either an existing target sticky or nil (the gateway then needs a drop frame to grow a new
/// sticky). Bundled — like `StickyFrame` — to keep `addConnector` within the parameter-count budget.
public struct ConnectorLink: Sendable {
    public let sourceStickyID: String
    public let sourceEdge: String
    public let targetStickyID: String?
    public let targetEdge: String

    public init(sourceStickyID: String, sourceEdge: String, targetStickyID: String?, targetEdge: String) {
        self.sourceStickyID = sourceStickyID
        self.sourceEdge = sourceEdge
        self.targetStickyID = targetStickyID
        self.targetEdge = targetEdge
    }
}

/// One end the model supplies to `reconnectConnector`: the sticky to attach to and the edge. A side
/// is either fully given (this struct) or omitted (`nil` → keep the current endpoint). Edges cross
/// the boundary as `CanvasEdge` raw values.
public struct ConnectorEndpointArg: Sendable {
    public let stickyID: String
    public let edge: String

    public init(stickyID: String, edge: String) {
        self.stickyID = stickyID
        self.edge = edge
    }
}

/// The style fields `editConnector` may change; nil means "keep". Bundled — like `StickyFrame` —
/// to keep the gateway method within the parameter-count budget.
public struct ConnectorStyleEdit: Sendable {
    public let cap: String?
    public let routing: String?
    public let strokeColorHex: String?
    public let strokeWidth: Double?

    public init(cap: String?, routing: String?, strokeColorHex: String?, strokeWidth: Double?) {
        self.cap = cap
        self.routing = routing
        self.strokeColorHex = strokeColorHex
        self.strokeWidth = strokeWidth
    }

    public var isEmpty: Bool {
        cap == nil && routing == nil && strokeColorHex == nil && strokeWidth == nil
    }
}

/// User-facing gateway failures. Surfaced to the model as the tool's error text.
public enum KanvasMCPError: Error, CustomStringConvertible {
    case badUUID(field: String, value: String)
    case badEnum(field: String, value: String, allowed: [String])
    case badSchedule(value: String)
    case badHexColor(field: String, value: String)
    case badBase64(field: String)
    case imageTooLarge(field: String, maxBytes: Int)
    case notPNG(field: String)
    case notFound(kind: String, id: String)
    case missingConnectorTarget
    case emptyConnectorEdit
    case halfSpecifiedConnectorSide(side: String)

    public var description: String {
        switch self {
        case let .badUUID(field, value):
            "Argument '\(field)' is not a valid UUID: \(value)"
        case let .badBase64(field):
            "Argument '\(field)' is not valid base64-encoded data"
        case let .imageTooLarge(field, maxBytes):
            "Argument '\(field)' exceeds the \(maxBytes)-byte image size limit"
        case let .notPNG(field):
            "Argument '\(field)' is not a PNG image (missing the PNG file signature)"
        case let .badEnum(field, value, allowed):
            "Argument '\(field)' must be one of [\(allowed.joined(separator: ", "))], got: \(value)"
        case let .badSchedule(value):
            "Argument 'schedule' must be 'none', 'YYYY-MM-DD' (deadline), or "
                + "'YYYY-MM-DD/YYYY-MM-DD' (period), got: \(value)"
        case let .badHexColor(field, value):
            "Argument '\(field)' must be a 6-digit RGB hex colour like '3478F6' "
                + "(RRGGBB, no leading '#'), got: \(value)"
        case let .notFound(kind, id):
            // Mirror `OperationError.notFound`'s wording verbatim ("\(kind) not found: \(id)") and
            // pass a capitalized `kind` ("Connector"/"Card"), so a stale id yields identical text
            // whether it surfaces from this gateway pre-check or the domain backstop (ticket
            // 0D2DE256). Keep the two in sync if either changes.
            "\(kind) not found: \(id)"
        case .missingConnectorTarget:
            "Provide either 'targetStickyID' (link an existing sticky) or 'x'/'y' "
                + "(grow a new sticky at that drop point)"
        case .emptyConnectorEdit:
            "Provide at least one of 'cap', 'routing', 'strokeColorHex', 'strokeWidth'"
        case let .halfSpecifiedConnectorSide(side):
            "The '\(side)' side is half-specified: provide both '\(side)StickyID' and '\(side)Edge', or neither"
        }
    }
}
