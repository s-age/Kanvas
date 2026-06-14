import Foundation

final class BoardManagementService: BoardManagementServiceProtocol, Sendable {
    private let repository: any BoardRepositoryProtocol
    /// Composes `ColumnService`'s pure transforms inside one `mutateBoard` for the board-settings
    /// save (settings + every column's colours / completion flag = one undo). The one sanctioned
    /// Service→Service dependency here (see `arch-domain-services.md` → "Multi-entity composition");
    /// only the pure transforms are used, never another mutate.
    private let columnService: any ColumnServiceProtocol
    /// Diagnostics port for the bootstrap recovery path: rebuilding a lost catalog from orphaned
    /// snapshots is a real data-integrity anomaly that must not stay silent (it previously did —
    /// the seed-on-any-`loadFailed` path destroyed existing boards with no log). See
    /// `bootstrapActiveBoard`.
    private let diagnostics: any DiagnosticsLoggingProtocol

    init(repository: any BoardRepositoryProtocol, columnService: any ColumnServiceProtocol,
         diagnostics: any DiagnosticsLoggingProtocol) {
        self.repository = repository
        self.columnService = columnService
        self.diagnostics = diagnostics
    }

    // MARK: Reads

    func loadActiveBoard() async throws -> BoardState {
        try await repository.loadActiveBoard()
    }

    func matchingCardIDs(query: String) async throws -> Set<UUID> {
        // Read-only, in-memory: load the active board (already fully in memory — no lazy loading)
        // and apply the pure `CardQuery` matcher. No `mutate`, so no lock / undo entry.
        let state = try await repository.loadActiveBoard()
        return matchingCardIDs(in: state, query: query)
    }

    func matchingCardIDs(in state: BoardState, query: String) -> Set<UUID> {
        // Pure: a caller that already holds the board (the combined view-state read) filters without
        // a second store read (PR #123 r2-1). Same `CardQuery` rule as the loading overload above.
        CardQuery.matchingCardIDs(in: state, query: query)
    }

    func bootstrapActiveBoard() async throws -> BoardState {
        do {
            return try await repository.loadActiveBoard()
        } catch OperationError.loadFailed, OperationError.fileCorrupted {
            // Neither error distinguishes a genuinely empty store from a *lost catalog over
            // surviving snapshots* — `loadFailed` is a missing `catalog.json`, `fileCorrupted` an
            // undecodable one, and both can sit over intact `boards/*.json`. Seeding unconditionally
            // would write a fresh single-board catalog and orphan every existing board — silent,
            // unrecoverable data loss. So establish the active board in priority order: migrate a
            // legacy single-board file, else recover any orphaned snapshots into a rebuilt catalog,
            // and only seed a Default-template board when no snapshot exists at all.
            if let migrated = try await repository.migrateLegacyBoard(resolvingCatalog: { board, catalog in
                self.registeringBoard(board, into: catalog)
            }) { return migrated }
            if let recovered = try await repository.recoverOrphanedBoards(resolvingCatalog: { catalog in
                self.recoveringActiveBoard(in: catalog)
            }) {
                diagnostics.log("bootstrap recovered a lost board catalog from surviving snapshots",
                                privateDetail: "active=\(recovered.board.id)", level: .error)
                return recovered
            }
            let seed = try await BoardState.from(template: repository.loadTemplate())
            return try await repository.insertBoard(seed) { catalog in
                self.registeringBoard(seed.board, into: catalog)
            }
        }
    }

    func bootstrapActiveBoardWithCatalog() async throws -> ActiveBoardSnapshot {
        do {
            return try await repository.loadActiveBoardWithCatalog()
        } catch OperationError.loadFailed, OperationError.fileCorrupted {
            // Cold or corrupt store: establish the active board through the full bootstrap recovery
            // (migrate legacy / recover orphans / seed default — see `bootstrapActiveBoard`), then
            // read the now-present catalog. Two reads here, but only on this rare establishing path;
            // the hot refresh path above is one read. Reusing `bootstrapActiveBoard` keeps the
            // recovery priority order single-sourced.
            let state = try await bootstrapActiveBoard()
            let catalog = try await repository.listBoards()
            return ActiveBoardSnapshot(state: state, boards: catalog.boards, activeBoardID: catalog.activeBoardID)
        }
    }

    func loadBoard(id: Board.ID) async throws -> BoardState {
        try await repository.loadBoard(id: id)
    }

    func listBoards() async throws -> BoardCatalog {
        try await repository.listBoards()
    }

    func loadTemplate() async throws -> BoardTemplate {
        try await repository.loadTemplate()
    }

    // MARK: Mutations

    func addBoard(title: String) async throws -> BoardState {
        // New boards inherit the app-level Default template (settings + column blueprint). Editing
        // the template later never reaches back into a board minted here.
        let template = try await repository.loadTemplate()
        let seed = BoardState.from(template: template, title: title)
        return try await repository.insertBoard(seed) { catalog in
            self.registeringBoard(seed.board, into: catalog)
        }
    }

    func registeringBoard(_ board: Board, into catalog: BoardCatalog) -> BoardCatalog {
        var next = catalog
        // Idempotent on the id: a re-insert (or a migrate over a catalog that somehow already lists
        // the board) must not duplicate the index entry. The new board always becomes active.
        if !next.boards.contains(where: { $0.id == board.id }) {
            next.boards.append(board)
        }
        next.activeBoardID = board.id
        return next
    }

    /// Picks which recovered board becomes active when a lost catalog is rebuilt from surviving
    /// snapshots. The Repository supplies the rebuilt index with `activeBoardID` set to the prior
    /// active id **only when its snapshot survived** (else `nil`); this keeps that survivor, and
    /// otherwise promotes the first recovered board. The same domain decision `deletingBoard` /
    /// `registeringBoard` own for their paths — hoisted out of inline Repository code (the 62FDA087
    /// family) so "which board is active" lives in exactly one layer. The Repository guarantees a
    /// non-empty `boards` before calling, so `first` resolves an id.
    func recoveringActiveBoard(in catalog: BoardCatalog) -> BoardCatalog {
        var next = catalog
        if let prior = next.activeBoardID, next.boards.contains(where: { $0.id == prior }) {
            return next
        }
        next.activeBoardID = next.boards.first?.id
        return next
    }

    func switchBoard(to id: Board.ID) async throws -> BoardState {
        try await repository.switchActiveBoard(to: id)
    }

    func renameBoard(id: Board.ID, title: String) async throws -> (boards: [Board], activeBoardID: UUID?) {
        try await repository.renameBoard(id: id, title: title)
    }

    func deleteBoard(id: Board.ID) async throws -> BoardState {
        // The Repository owns the mechanism (reload under lock, catalog-before-file ordering); the
        // domain decision — next active board + last-board protection — is this Service's pure
        // `deletingBoard`, applied inside the lock the Repository holds.
        try await repository.deleteBoard(id: id) { catalog in
            try self.deletingBoard(id: id, from: catalog)
        }
    }

    func deletingBoard(id: Board.ID, from catalog: BoardCatalog) throws -> BoardCatalog {
        // Deleting an id the catalog never held is a caller error, not a silent success — mirror
        // `renameBoard`, which already throws `notFound` for an unknown board (the asymmetry this
        // strict-ifies). Checked before removal so a bogus id can't masquerade as a no-op delete.
        guard catalog.boards.contains(where: { $0.id == id }) else {
            throw OperationError.notFound(entityKind: "Board", id: id)
        }
        var next = catalog
        next.boards.removeAll { $0.id == id }
        // The last remaining board may not be deleted — there must always be an active board.
        guard !next.boards.isEmpty else {
            throw OperationError.inconsistentState(reason: "Deleted the last remaining board")
        }
        // Deleting the active board promotes the catalog's first remaining board; deleting any other
        // board leaves the active one untouched.
        if catalog.activeBoardID == id {
            next.activeBoardID = next.boards.first?.id
        }
        return next
    }

    func undo() async throws -> UndoOutcome {
        try await repository.undo()
    }

    func saveTemplate(_ template: BoardTemplate) async throws {
        try await repository.saveTemplate(template)
    }

    func editBoardSettings(boardID: Board.ID, settings: BoardSettings,
                             columns: [ColumnAppearanceUpdate]) async throws -> BoardState {
        // Settings + every column's colours / completion flag commit together, so a single "Save"
        // is one undo entry and one disk write. `mutateBoard` targets the given board without
        // switching the active one (the settings sidebar can edit any board).
        try await repository.mutateBoard(id: boardID) { state in
            var next = state
            next.settings = settings
            next = try columns.reduce(next) { acc, column in
                try self.columnService.settingColors(id: column.id, colors: column.colors, in: acc)
            }
            // One column flagged ⇒ it becomes the sole completion column; none ⇒ clear every listed
            // column's flag. Applied after settings so completedAt reconciliation sees the new
            // `autoCompleteOnMove`.
            // NOTE: the "none flagged" branch clears only the *passed* `columns`, not `state.columns`.
            // This is correct because the sole caller — the settings sidebar (`EditBoardSettings`) —
            // always passes the board's full column set, so any previously-flagged column is in
            // `columns` and gets cleared. If a future partial-update caller passes a subset, a stale
            // completion flag on an omitted column would survive; such a caller should reduce over
            // `state.columns` instead.
            if let completionID = columns.first(where: \.isCompletionColumn)?.id {
                next = try self.columnService.settingCompletion(id: completionID, isCompletion: true, in: next)
            } else {
                next = try columns.reduce(next) { acc, column in
                    try self.columnService.settingCompletion(id: column.id, isCompletion: false, in: acc)
                }
            }
            return next
        }
    }

    func editColumnAppearance(
        columnID: Column.ID, edit: ColumnAppearanceFields
    ) async throws -> BoardState {
        // One column's keep/clear/set colours + completion flag on the **active** board, resolved
        // **inside** the mutation against the column reloaded from disk under the store lock. This
        // replaces the MCP gateway's former load-active-board-then-batch-write across two flocks,
        // which could clobber a sibling column edited by the app or another MCP process in the
        // read-write window (ticket 620B3601). One logical mutation = one `mutate` = one undo entry.
        try await repository.mutate { state in
            // Resolve keep/clear/set per field inline against the live column — same shape as
            // `CardService.editing` resolves `EditCardFields` (`if let x = edit.x { … }`), so the
            // edit-bag entity stays pure data. A `nil` outer optional keeps the current value;
            // `.some(value)` (clear sentinel `.some(nil)` or a set hex) overrides it.
            let idx = try state.requireIndex(of: columnID, in: \.columns, entityKind: "Column")
            let column = state.columns[idx]
            let resolved = ColumnColors(
                headerColorHex: edit.headerColorHex ?? column.headerColorHex,
                headerTextColorHex: edit.headerTextColorHex ?? column.headerTextColorHex,
                bodyColorHex: edit.bodyColorHex ?? column.bodyColorHex,
                headerBorderColorHex: edit.headerBorderColorHex ?? column.headerBorderColorHex,
                bodyBorderColorHex: edit.bodyBorderColorHex ?? column.bodyBorderColorHex,
                indicatorColorHex: edit.indicatorColorHex ?? column.indicatorColorHex
            )
            var next = try self.columnService.settingColors(id: columnID, colors: resolved, in: state)
            // `settingCompletion(isCompletion: true)` clears every sibling's flag, so promoting the
            // target to the completion column always leaves exactly one true flag — the GUI's
            // single-select picker invariant, enforced here for the MCP path too. Omitted ⇒ untouched.
            if let isCompletion = edit.isCompletionColumn {
                next = try self.columnService.settingCompletion(
                    id: columnID, isCompletion: isCompletion, in: next
                )
            }
            return next
        }
    }
}
