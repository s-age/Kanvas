import KanvasCore
import MCP

/// `board_*` tools — the Kanban top level (boards, columns, cards). All operate on the active board
/// except `board_get`, which can target any board by `boardID`.
func boardTools(_ gateway: KanvasMCPGateway) -> [any MCPTool] {
    [
        ClosureTool(
            name: "board_list",
            description: "List all boards and which one is active. Returns {activeBoardID, boards:[{id,title}]}.",
            inputSchema: objectSchema([])
        ) { _ in try await gateway.listBoards() },

        ClosureTool(
            name: "board_get",
            description: "Get a board's columns and cards. Omit 'boardID' for the active board. Returns the board with its columns, each column's cards (id, title, status). To see a card's canvas/stickies use canvas_get; for its Markdown use markdown_get.",
            inputSchema: objectSchema([
                ("boardID", "string", "Board UUID. Omit for the active board.", false),
            ])
        ) { args in try await gateway.getBoard(id: try args.optionalString("boardID")) },

        ClosureTool(
            name: "board_card_add",
            description: "Add a card to a column on the active board. Returns the new card's id and the refreshed board.",
            inputSchema: objectSchema([
                ("columnID", "string", "UUID of the target column.", true),
                ("title", "string", "Card title (non-empty).", true),
                ("markdown", "string", "Optional initial Markdown detail for the card.", false),
            ])
        ) { args in
            try await gateway.addCard(
                columnID: args.string("columnID"),
                title: args.string("title"),
                markdown: try args.optionalString("markdown")
            )
        },

        ClosureTool(
            name: "board_card_edit",
            description: "Edit a card's title, Markdown, assignee, and/or schedule. Omit a field to leave it unchanged. A card's status is its column — change status with board_card_move, not here.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card to edit.", true),
                ("title", "string", "New title (omit to keep).", false),
                ("markdown", "string", "New Markdown detail (omit to keep).", false),
                ("assignee", "string", "New assignee (omit to keep; empty string to clear).", false),
                ("schedule", "string", "New schedule: 'YYYY-MM-DD' for a deadline, 'YYYY-MM-DD/YYYY-MM-DD' for a period, 'none' to clear (omit to keep).", false),
            ])
        ) { args in
            try await gateway.editCard(
                cardID: args.string("cardID"),
                title: try args.optionalString("title"),
                markdown: try args.optionalString("markdown"),
                assignee: try args.optionalString("assignee"),
                schedule: try args.optionalString("schedule")
            )
        },

        ClosureTool(
            name: "board_card_set_pr_url",
            description: "Set (or clear) ONLY a card's linked PR URL, leaving title/Markdown/status/etc. unchanged. Token-light way to associate a ticket with its pull request. Pass an empty string to clear. Returns the minimal {cardID, title, prURL}. To read the current PR URL back, use canvas_get (board_get/board_card_edit do not expose it).",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("url", "string", "The PR URL to link, or an empty string to clear it.", true),
            ])
        ) { args in
            try await gateway.setCardPRURL(cardID: args.string("cardID"), url: args.string("url"))
        },

        ClosureTool(
            name: "board_card_move",
            description: "Move a card to a column. Drops it before 'beforeCardID', or appends to the end when that is omitted.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card to move.", true),
                ("toColumnID", "string", "UUID of the destination column.", true),
                ("beforeCardID", "string", "UUID of the card to insert before; omit to append.", false),
            ])
        ) { args in
            try await gateway.moveCard(
                cardID: args.string("cardID"),
                toColumnID: args.string("toColumnID"),
                beforeCardID: try args.optionalString("beforeCardID")
            )
        },

        ClosureTool(
            name: "board_card_delete",
            description: "Delete a card from the active board. Returns the refreshed board.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card to delete.", true),
            ])
        ) { args in try await gateway.deleteCard(cardID: args.string("cardID")) },

        ClosureTool(
            name: "board_column_add",
            description: "Add a column to the active board. Returns the refreshed board.",
            inputSchema: objectSchema([
                ("title", "string", "Column title (non-empty).", true),
            ])
        ) { args in try await gateway.addColumn(title: args.string("title")) },

        ClosureTool(
            name: "board_column_rename",
            description: "Rename a column on the active board. Returns the refreshed board.",
            inputSchema: objectSchema([
                ("columnID", "string", "UUID of the column.", true),
                ("title", "string", "New title (non-empty).", true),
            ])
        ) { args in
            try await gateway.renameColumn(columnID: args.string("columnID"), title: args.string("title"))
        },

        ClosureTool(
            name: "board_column_delete",
            description: "Delete a column from the active board. Returns the refreshed board.",
            inputSchema: objectSchema([
                ("columnID", "string", "UUID of the column to delete.", true),
            ])
        ) { args in try await gateway.deleteColumn(columnID: args.string("columnID")) },

        ClosureTool(
            name: "board_column_appearance_edit",
            description: "Edit ONE column's appearance — its colours and/or its completion flag — on the active board, leaving every other column and all board-level settings untouched. This mirrors the app's Settings > Board per-column editor. Colour fields take a bare 6-digit RGB hex string 'RRGGBB' (no leading '#', e.g. '3478F6') — the same format board_get returns. Per colour field the convention is: OMIT the key to leave it unchanged; pass an EMPTY string to clear it back to the system default; pass a hex string to set it. Omit 'isCompletionColumn' to leave it unchanged. Returns the refreshed board.",
            inputSchema: objectSchema([
                ("columnID", "string", "UUID of the column to restyle.", true),
                ("headerColorHex", "string", "Header background colour (hex). Omit to keep; empty string clears to default.", false),
                ("headerTextColorHex", "string", "Header text colour (hex). Omit to keep; empty string clears to default.", false),
                ("bodyColorHex", "string", "Body (card-stack area) background colour (hex). Omit to keep; empty string clears to default.", false),
                ("headerBorderColorHex", "string", "Header border colour (hex). Omit to keep; empty string clears to default.", false),
                ("bodyBorderColorHex", "string", "Body border colour (hex). Omit to keep; empty string clears to default.", false),
                ("indicatorColorHex", "string", "Status-indicator dot colour (hex). Omit to keep; empty string clears to the neutral default.", false),
                ("isCompletionColumn", "boolean", "Whether this column marks cards complete. Omit to keep unchanged.", false),
            ])
        ) { args in
            try await gateway.editColumnAppearance(
                columnID: args.string("columnID"),
                appearance: ColumnAppearanceEdit(
                    headerColorHex: try args.optionalString("headerColorHex"),
                    headerTextColorHex: try args.optionalString("headerTextColorHex"),
                    bodyColorHex: try args.optionalString("bodyColorHex"),
                    headerBorderColorHex: try args.optionalString("headerBorderColorHex"),
                    bodyBorderColorHex: try args.optionalString("bodyBorderColorHex"),
                    indicatorColorHex: try args.optionalString("indicatorColorHex"),
                    isCompletionColumn: try args.optionalBool("isCompletionColumn")
                )
            )
        },
    ]
}
