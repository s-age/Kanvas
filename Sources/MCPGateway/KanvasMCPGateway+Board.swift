import Foundation

/// `board_*` operations — the Kanban top level (boards, columns, cards). All return JSON. Reads echo
/// the requested view; write ops echo a **token-light** result scoped to what changed (the affected
/// card via `CardEchoOut`, the column list via `BoardColumnsOut`, or `{deletedID}`) — never the whole
/// board, whose card summaries dwarf the edit (hundreds of cards on a busy board). The model re-reads
/// the full board with `board_get` only when it needs it.
extension KanvasMCPGateway {

    public func listBoards() async throws -> String {
        let response = try await listBoardsUseCase.execute(ListBoardsRequest())
        return try MCPJSON.encode(BoardListOut(response))
    }

    /// Loads a board by id, or the active board when `id` is nil.
    public func getBoard(id: String?) async throws -> String {
        let response: BoardResponse
        if let id {
            response = try await loadBoardByIDUseCase.execute(LoadBoardByIDRequest(boardID: uuid(id, "id")))
        } else {
            response = try await loadActiveBoardUseCase.execute(LoadActiveBoardRequest())
        }
        return try MCPJSON.encode(BoardOut(response))
    }

    /// Adds a card to a column on the active board, optionally seeding its Markdown — one atomic
    /// mutation (one undo step). The UseCase reports the new card's id directly.
    public func addCard(columnID: String, title: String, markdown: String?) async throws -> String {
        let response = try await addCardUseCase.execute(AddCardRequest(
            title: title,
            columnID: uuid(columnID, "columnID"),
            markdownContent: markdown
        ))
        return try MCPJSON.encode(
            CardCreatedOut(newCardID: response.newCardID, board: BoardOut(response.board))
        )
    }

    /// Edits a card's title / Markdown / assignee / schedule. Each argument is optional —
    /// omit to leave unchanged. `assignee` clears on an empty/blank string (the blank→nil
    /// normalization lives in `EditCardUseCaseImpl`); `schedule` takes "none", "YYYY-MM-DD", or
    /// "YYYY-MM-DD/YYYY-MM-DD" (see `scheduleValue`). A card's status is its column — change it via
    /// `moveCard`, not here.
    public func editCard(
        cardID: String,
        title: String? = nil,
        markdown: String? = nil,
        assignee: String? = nil,
        schedule: String? = nil
    ) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await editCardUseCase.execute(
            editCardRequest(
                cardID: id, title: title, markdown: markdown,
                assignee: Self.requestEdit(assignee), schedule: try Self.scheduleEdit(schedule)
            )
        )
        return try MCPJSON.encode(Self.locateCard(result.board, id: id))
    }

    /// Sets (or clears) **only** a card's linked PR URL, leaving every other field untouched — the
    /// token-light path for associating a ticket with the PR Claude opened for it. Pass an empty or
    /// blank `url` to clear the link (normalized to nil at the UseCase boundary). Echoes the minimal
    /// `{cardID, title, prURL}` so the model confirms the new value without re-reading the canvas.
    /// (Reuses the `cardDetail` helper that lives next to the other read paths in `+Canvas`.)
    public func setCardPRURL(cardID: String, url: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await editCardUseCase.execute(EditCardRequest(cardID: id, prURL: .some(url)))
        let detail = try await echoDetail(result, cardID: id)
        return try MCPJSON.encode(
            CardPRURLOut(cardID: detail.id, title: detail.title, prURL: detail.prURL)
        )
    }

    /// Moves a card to a column, dropping it before `beforeCardID` (or appending when nil).
    public func moveCard(cardID: String, toColumnID: String, beforeCardID: String?) async throws -> String {
        let id = try uuid(cardID, "cardID")
        let result = try await moveCardUseCase.execute(MoveCardRequest(
            cardID: id,
            toColumnID: uuid(toColumnID, "toColumnID"),
            beforeCardID: try beforeCardID.map { try uuid($0, "beforeCardID") }
        ))
        return try MCPJSON.encode(Self.locateCard(result.board, id: id))
    }

    public func deleteCard(cardID: String) async throws -> String {
        let id = try uuid(cardID, "cardID")
        _ = try await deleteCardUseCase.execute(DeleteCardRequest(cardID: id))
        return try MCPJSON.encode(DeletedOut(deletedID: id))
    }

    public func addColumn(title: String) async throws -> String {
        let board = try await addColumnUseCase.execute(AddColumnRequest(title: title))
        return try MCPJSON.encode(BoardColumnsOut(board))
    }

    public func renameColumn(columnID: String, title: String) async throws -> String {
        let board = try await renameColumnUseCase.execute(
            RenameColumnRequest(columnID: uuid(columnID, "columnID"), title: title)
        )
        return try MCPJSON.encode(BoardColumnsOut(board))
    }

    public func deleteColumn(columnID: String) async throws -> String {
        let board = try await deleteColumnUseCase.execute(DeleteColumnRequest(columnID: uuid(columnID, "columnID")))
        return try MCPJSON.encode(BoardColumnsOut(board))
    }

    /// Edits **one** column's appearance (the five colour fields + the indicator dot) and/or its
    /// completion flag on the active board, leaving every other column and every board-level setting
    /// untouched.
    ///
    /// Delegates to `EditColumnAppearanceUseCase`, which resolves the keep/clear/set overlay and the
    /// single-completion-column invariant **inside one `mutateBoard`** against the column reloaded
    /// under the store lock. So the whole read-modify-write is one atomic mutation (one undo entry)
    /// with no lost-update window for sibling columns edited concurrently by the app or another MCP
    /// process — the TOCTOU this method previously had (load-active-board then a *separate* batch
    /// save) is gone. (ticket 620B3601; the single-completion enforcement is 5C8D8944.)
    ///
    /// Null-vs-omitted convention (per field): a `nil` argument (the tool key was omitted) **keeps**
    /// the column's current value; an **empty string** **clears** the field to the system default
    /// (`nil`); any other string **sets** it. `isCompletionColumn` is a plain optional — `nil` keeps,
    /// a bool sets. Hex format is checked here (the GUI uses a colour picker), before the mutation;
    /// the column-not-found backstop is the use case's `requireIndex` throw inside the lock.
    public func editColumnAppearance(
        columnID: String,
        appearance: ColumnAppearanceEdit
    ) async throws -> String {
        let id = try uuid(columnID, "columnID")
        try Self.validateHexFields(appearance)
        let response = try await editColumnAppearanceUseCase.execute(EditColumnAppearanceRequest(
            columnID: id,
            headerColorHex: Self.keepClearSet(appearance.headerColorHex),
            headerTextColorHex: Self.keepClearSet(appearance.headerTextColorHex),
            bodyColorHex: Self.keepClearSet(appearance.bodyColorHex),
            headerBorderColorHex: Self.keepClearSet(appearance.headerBorderColorHex),
            bodyBorderColorHex: Self.keepClearSet(appearance.bodyBorderColorHex),
            indicatorColorHex: Self.keepClearSet(appearance.indicatorColorHex),
            isCompletionColumn: appearance.isCompletionColumn
        ))
        return try MCPJSON.encode(BoardColumnsOut(response))
    }

    /// Translates one colour argument from the MCP string sentinel into the Request's double-optional
    /// keep/clear/set intent: `nil` (omitted) → `nil` (keep); `""` (the clear sentinel) → `.some(nil)`
    /// (clear to system default); any other string → `.some(.some(value))` (set). The actual overlay
    /// against the live column happens in the domain (`BoardManagementService.editColumnAppearance`);
    /// this only maps the wire sentinel. Static + pure so the convention is pinned by unit tests.
    static func keepClearSet(_ argument: String?) -> String?? {
        guard let argument else { return nil }
        return argument.isEmpty ? .some(nil) : .some(argument)
    }

    /// Rejects a malformed colour before it is written to persistence. The tool description promises
    /// a bare 6-digit RGB hex like `3478F6`; without this guard the MCP path (unlike the GUI's picker)
    /// could persist garbage that render-time silently treats as "no colour". `nil` (omit) and `""`
    /// (clear) are valid per the keep/clear convention — only a *set* value is format-checked.
    /// (ticket 5C8D8944, review r1-3)
    static func validateHexFields(_ edit: ColumnAppearanceEdit) throws {
        let fields: [(String, String?)] = [
            ("headerColorHex", edit.headerColorHex),
            ("headerTextColorHex", edit.headerTextColorHex),
            ("bodyColorHex", edit.bodyColorHex),
            ("headerBorderColorHex", edit.headerBorderColorHex),
            ("bodyBorderColorHex", edit.bodyBorderColorHex),
            ("indicatorColorHex", edit.indicatorColorHex)
        ]
        for (name, value) in fields {
            guard let value, !value.isEmpty else { continue }  // nil = keep, "" = clear
            guard Self.isValidHexColor(value) else {
                throw KanvasMCPError.badHexColor(field: name, value: value)
            }
        }
    }

    /// Bare 6-digit `RRGGBB` (no leading `#`, hex digits only) — the single format the whole system
    /// agrees on: the store seed (`BoardTemplate`), the GUI's `Color.toHex`, and every other hex
    /// field via `LabelValidation.validate(colorHex:)` all use bare 6-digit. So an LLM round-tripping
    /// a colour read from `board_get` (which is bare 6-digit) is accepted, and the persisted value
    /// stays format-consistent with the rest of the store. This mirrors the same check
    /// `EditColumnAppearanceRequest.validate()` now runs in the Request layer; the gateway keeps a
    /// field-aware copy so the error names the offending colour field. (ticket C5994D2A)
    static func isValidHexColor(_ value: String) -> Bool {
        value.count == 6 && value.allSatisfy(\.isHexDigit)
    }

    /// Finds a card and the column holding it in a refreshed board response, for the single-card
    /// write echoes (`editCard` / `moveCard`). Throws `notFound` if the id is absent — the card was
    /// just written, so a miss means a concurrent foreign delete landed between the mutation and this
    /// read (the shared multi-process store); surfacing it beats echoing a card that no longer exists.
    static func locateCard(_ board: BoardResponse, id: UUID) throws -> CardEchoOut {
        for column in board.columns {
            if let card = column.cards.first(where: { $0.id == id }) {
                return CardEchoOut(card, columnID: column.id)
            }
        }
        throw KanvasMCPError.notFound(kind: "Card", id: id.uuidString)
    }

    /// Builds an `EditCardRequest` that changes only the given fields (the rest stay unchanged via
    /// the request's "no change" sentinels — `nil` for the single-optionals, `.none` for the
    /// schedule/assignee double-optionals).
    private func editCardRequest(
        cardID: UUID, title: String? = nil, markdown: String? = nil,
        assignee: String?? = nil, schedule: ScheduleInput?? = nil
    ) -> EditCardRequest {
        EditCardRequest(
            cardID: cardID,
            title: title,
            markdownContent: markdown,
            schedule: schedule,
            labels: nil,
            assignee: assignee
        )
    }
}
