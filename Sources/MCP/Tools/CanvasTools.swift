import KanvasCore
import MCP

/// `canvas_*` tools — a card's spatial canvas: stickies plus the connectors linking them.
/// Coordinates `x`/`y` are the sticky's centre in canvas units; `width`/`height` its size. Every
/// write returns the card's refreshed canvas (CardDetailOut), so the model sees the result without
/// a follow-up read.
func canvasTools(_ gateway: KanvasMCPGateway) -> [any MCPTool] {
    [
        ClosureTool(
            name: "canvas_get",
            description: "Get a card's canvas: its Markdown, status, all stickies (id, content, isTask, x, y, width, height, colors), all free-text objects (id, content, x, y, width, height, color, fontSize), and all connectors (id, endpoints, cap, routing, stroke), plus counts of shapes/images.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card whose canvas to load.", true),
            ])
        ) { args in try await gateway.getCanvas(cardID: args.string("cardID")) },

        ClosureTool(
            name: "canvas_sticky_add",
            description: "Add a sticky to a card's canvas. x/y are the sticky centre; width/height its size. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("content", "string", "Sticky text.", true),
                ("x", "number", "Centre x in canvas units.", true),
                ("y", "number", "Centre y in canvas units.", true),
                ("width", "number", "Width in canvas units.", true),
                ("height", "number", "Height in canvas units.", true),
                ("fillColorHex", "string", "Optional fill colour 'RRGGBB'; omit to inherit the board default.", false),
            ])
        ) { args in
            try await gateway.addSticky(
                cardID: args.string("cardID"),
                content: args.string("content"),
                frame: StickyFrame(x: try args.double("x"), y: try args.double("y"),
                                   width: try args.double("width"), height: try args.double("height")),
                fillColorHex: try args.optionalString("fillColorHex")
            )
        },

        ClosureTool(
            name: "canvas_sticky_edit",
            description: "Change a sticky's text. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky.", true),
                ("content", "string", "New sticky text.", true),
            ])
        ) { args in
            try await gateway.editSticky(
                cardID: args.string("cardID"), stickyID: args.string("stickyID"), content: args.string("content")
            )
        },

        ClosureTool(
            name: "canvas_sticky_move",
            description: "Move a sticky to a new centre (x, y). Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky.", true),
                ("x", "number", "New centre x.", true),
                ("y", "number", "New centre y.", true),
            ])
        ) { args in
            try await gateway.moveSticky(
                cardID: args.string("cardID"), stickyID: args.string("stickyID"),
                x: try args.double("x"), y: try args.double("y")
            )
        },

        ClosureTool(
            name: "canvas_sticky_set_frame",
            description: "Set a sticky's full frame — width, height, AND centre (x, y) — in one undo step. All four are required: this is not a pure resize, it repositions the centre too (use canvas_sticky_move to set only the centre). Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky.", true),
                ("width", "number", "New width.", true),
                ("height", "number", "New height.", true),
                ("x", "number", "New centre x.", true),
                ("y", "number", "New centre y.", true),
            ])
        ) { args in
            try await gateway.setStickyFrame(
                cardID: args.string("cardID"), stickyID: args.string("stickyID"),
                frame: StickyFrame(x: try args.double("x"), y: try args.double("y"),
                                   width: try args.double("width"), height: try args.double("height"))
            )
        },

        ClosureTool(
            name: "canvas_sticky_delete",
            description: "Delete a sticky from a card's canvas. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky to delete.", true),
            ])
        ) { args in
            try await gateway.deleteSticky(cardID: args.string("cardID"), stickyID: args.string("stickyID"))
        },

        ClosureTool(
            name: "canvas_sticky_promote",
            description: "Promote a free sticky into a task sticky: creates a card in 'toColumnID' and links the sticky to it. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky to promote.", true),
                ("toColumnID", "string", "UUID of the column to create the linked card in.", true),
            ])
        ) { args in
            try await gateway.promoteSticky(
                cardID: args.string("cardID"), stickyID: args.string("stickyID"), toColumnID: args.string("toColumnID")
            )
        },

        ClosureTool(
            name: "canvas_sticky_demote",
            description: "Demote a task sticky back to a free sticky, clearing its Kanban link. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the sticky.", true),
                ("stickyID", "string", "UUID of the sticky to demote.", true),
            ])
        ) { args in
            try await gateway.demoteSticky(cardID: args.string("cardID"), stickyID: args.string("stickyID"))
        },

        ClosureTool(
            name: "canvas_text_add",
            description: "Add a free-text object (background/border-less text) to a card's canvas. x/y are the centre; width/height the box (text wraps to width and is clipped at height). Content may be empty. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card.", true),
                ("content", "string", "Text body.", true),
                ("x", "number", "Centre x in canvas units.", true),
                ("y", "number", "Centre y in canvas units.", true),
                ("width", "number", "Width in canvas units.", true),
                ("height", "number", "Height in canvas units.", true),
            ])
        ) { args in
            try await gateway.addText(
                cardID: args.string("cardID"),
                content: args.string("content"),
                frame: StickyFrame(x: try args.double("x"), y: try args.double("y"),
                                   width: try args.double("width"), height: try args.double("height"))
            )
        },

        ClosureTool(
            name: "canvas_text_edit",
            description: "Edit a free-text object's content and, optionally, its style (textColorHex / fontSize) in one call. Omitted style fields keep their value. An empty content deletes the text object. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the text.", true),
                ("textID", "string", "UUID of the text object.", true),
                ("content", "string", "New text body (empty deletes the object).", true),
                ("textColorHex", "string", "Optional text colour 'RRGGBB'.", false),
                ("fontSize", "number", "Optional font size (clamped to 8\u{2013}96).", false),
            ])
        ) { args in
            try await gateway.editText(
                cardID: args.string("cardID"),
                textID: args.string("textID"),
                content: args.string("content"),
                style: TextStyleEdit(
                    colorHex: try args.optionalString("textColorHex"),
                    fontSize: try args.optionalDouble("fontSize")
                )
            )
        },

        ClosureTool(
            name: "canvas_text_move",
            description: "Move a free-text object to a new centre (x, y). Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the text.", true),
                ("textID", "string", "UUID of the text object.", true),
                ("x", "number", "New centre x.", true),
                ("y", "number", "New centre y.", true),
            ])
        ) { args in
            try await gateway.moveText(
                cardID: args.string("cardID"), textID: args.string("textID"),
                x: try args.double("x"), y: try args.double("y")
            )
        },

        ClosureTool(
            name: "canvas_text_set_frame",
            description: "Set a free-text object's full frame — width, height, AND centre (x, y) — in one undo step. Text wraps to width and is clipped at height. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the text.", true),
                ("textID", "string", "UUID of the text object.", true),
                ("width", "number", "New width.", true),
                ("height", "number", "New height.", true),
                ("x", "number", "New centre x.", true),
                ("y", "number", "New centre y.", true),
            ])
        ) { args in
            try await gateway.setTextFrame(
                cardID: args.string("cardID"), textID: args.string("textID"),
                frame: StickyFrame(x: try args.double("x"), y: try args.double("y"),
                                   width: try args.double("width"), height: try args.double("height"))
            )
        },

        ClosureTool(
            name: "canvas_text_delete",
            description: "Delete a free-text object from a card's canvas. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the text.", true),
                ("textID", "string", "UUID of the text object to delete.", true),
            ])
        ) { args in
            try await gateway.deleteText(cardID: args.string("cardID"), textID: args.string("textID"))
        },

        ClosureTool(
            name: "canvas_connector_add",
            description: "Connect two stickies with an arrow/line, from the source sticky's edge to the target's. Pass 'targetStickyID' to link an existing sticky, or 'x'/'y' (and optionally 'width'/'height') instead to grow a new empty sticky at that drop point and link it. When 'targetStickyID' is set, x/y/width/height are ignored. Cap/routing default (arrow, straight). Omit 'strokeColorHex' to inherit the canvas-contrasting default colour (#333 on a light background, #ddd on a dark one); set it to choose the stroke colour at creation. Restyle further via canvas_connector_edit. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card whose canvas owns both stickies.", true),
                ("sourceStickyID", "string", "UUID of the sticky the connector starts from.", true),
                ("sourceEdge", "string", "Edge it leaves from: 'top' | 'bottom' | 'left' | 'right'.", true),
                ("targetEdge", "string", "Edge it arrives at: 'top' | 'bottom' | 'left' | 'right'.", true),
                ("targetStickyID", "string", "UUID of an existing sticky to connect to. Omit to grow a new sticky at x/y instead.", false),
                ("x", "number", "New sticky's centre x — required when targetStickyID is omitted.", false),
                ("y", "number", "New sticky's centre y — required when targetStickyID is omitted.", false),
                ("width", "number", "New sticky's width; defaults to 200.", false),
                ("height", "number", "New sticky's height; defaults to 150.", false),
                ("strokeColorHex", "string", "Stroke colour 'RRGGBB'. Omit to inherit the canvas-contrasting default.", false),
            ])
        ) { args in
            let targetStickyID = try args.optionalString("targetStickyID")
            return try await gateway.addConnector(
                cardID: args.string("cardID"),
                link: ConnectorLink(
                    sourceStickyID: try args.string("sourceStickyID"),
                    sourceEdge: try args.string("sourceEdge"),
                    targetStickyID: targetStickyID,
                    targetEdge: try args.string("targetEdge")
                ),
                dropFrame: try connectorDropFrame(args, hasTarget: targetStickyID != nil),
                strokeColorHex: try args.optionalString("strokeColorHex")
            )
        },

        ClosureTool(
            name: "canvas_connector_edit",
            description: "Restyle a connector: endpoint cap, path routing, stroke colour, stroke width. Provide at least one field; omitted fields keep their value. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the connector.", true),
                ("connectorID", "string", "UUID of the connector.", true),
                ("cap", "string", "Endpoint cap: 'line' | 'arrow'.", false),
                ("routing", "string", "Path routing: 'straight' | 'elbow' | 'curve'.", false),
                ("strokeColorHex", "string", "Stroke colour 'RRGGBB'.", false),
                ("strokeWidth", "number", "Stroke width in canvas units (clamped to 1\u{2013}40).", false),
            ])
        ) { args in
            try await gateway.editConnector(
                cardID: args.string("cardID"),
                connectorID: args.string("connectorID"),
                style: ConnectorStyleEdit(
                    cap: try args.optionalString("cap"),
                    routing: try args.optionalString("routing"),
                    strokeColorHex: try args.optionalString("strokeColorHex"),
                    strokeWidth: try args.optionalDouble("strokeWidth")
                )
            )
        },

        ClosureTool(
            name: "canvas_connector_reconnect",
            description: "Re-attach a connector's endpoint(s) to a different sticky and/or edge. Provide the source side (sourceStickyID + sourceEdge) and/or the target side (targetStickyID + targetEdge); an omitted side keeps its current endpoint. To move only an endpoint's edge, pass that side with the SAME stickyID and a new edge. Each side is all-or-nothing: give both its stickyID and edge, or neither. Provide at least one side. A reconnect that would link a sticky to itself is rejected. Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the connector.", true),
                ("connectorID", "string", "UUID of the connector to reconnect.", true),
                ("sourceStickyID", "string", "UUID of the sticky the source end should attach to. Pass with sourceEdge.", false),
                ("sourceEdge", "string", "Source end edge: 'top' | 'bottom' | 'left' | 'right'. Pass with sourceStickyID.", false),
                ("targetStickyID", "string", "UUID of the sticky the target end should attach to. Pass with targetEdge.", false),
                ("targetEdge", "string", "Target end edge: 'top' | 'bottom' | 'left' | 'right'. Pass with targetStickyID.", false),
            ])
        ) { args in
            try await gateway.reconnectConnector(
                cardID: args.string("cardID"),
                connectorID: args.string("connectorID"),
                source: try connectorEndpointArg(args, stickyKey: "sourceStickyID", edgeKey: "sourceEdge", side: "source"),
                target: try connectorEndpointArg(args, stickyKey: "targetStickyID", edgeKey: "targetEdge", side: "target")
            )
        },

        ClosureTool(
            name: "canvas_connector_delete",
            description: "Delete a connector from a card's canvas (the stickies it linked are untouched). Returns the refreshed canvas.",
            inputSchema: objectSchema([
                ("cardID", "string", "UUID of the card owning the connector.", true),
                ("connectorID", "string", "UUID of the connector to delete.", true),
            ])
        ) { args in
            try await gateway.deleteConnector(
                cardID: args.string("cardID"), connectorID: args.string("connectorID")
            )
        },
    ]
}

/// Assembles a `canvas_connector_reconnect` side from its flat (stickyID, edge) key pair:
/// - both omitted → `nil` (keep this endpoint)
/// - both present → build the arg
/// - exactly one present → a half-specified side. Reject it here with `halfSpecifiedConnectorSide`,
///   which names the side and both required keys — rather than forwarding `stickyID ?? ""` and
///   letting an empty `""` surface downstream as a confusing `badUUID(value: "")` (edge-without-id
///   used to feed `""` into the gateway's UUID parse). `side` is the shared prefix of the two keys
///   ("source" / "target"), so the message names the exact keys the model must pass together.
func connectorEndpointArg(_ args: Arguments, stickyKey: String, edgeKey: String, side: String) throws -> ConnectorEndpointArg? {
    let stickyID = try args.optionalString(stickyKey)
    let edge = try args.optionalString(edgeKey)
    switch (stickyID, edge) {
    case (nil, nil): return nil
    case let (id?, edge?): return ConnectorEndpointArg(stickyID: id, edge: edge)
    default: throw KanvasMCPError.halfSpecifiedConnectorSide(side: side)
    }
}

/// Derives `canvas_connector_add`'s optional drop frame from its either/or argument shape:
/// - target given → nil; any x/y/width/height is ignored (the tool description says so)
/// - neither x nor y → nil; the gateway's `missingConnectorTarget` then explains both options,
///   which beats a bare missing-key error
/// - x or y given → the model committed to the drop branch, so require **both**; the missing-key
///   error then names exactly the forgotten coordinate. width/height default to the app's
///   grow-gesture size (200×150 when no preset is configured; the domain re-clamps on creation).
func connectorDropFrame(_ args: Arguments, hasTarget: Bool) throws -> StickyFrame? {
    if hasTarget { return nil }
    guard try args.optionalDouble("x") != nil || args.optionalDouble("y") != nil else { return nil }
    return StickyFrame(
        x: try args.double("x"), y: try args.double("y"),
        width: try args.optionalDouble("width") ?? 200,
        height: try args.optionalDouble("height") ?? 150
    )
}
