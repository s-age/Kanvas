import XCTest
@testable import KanvasCore

/// `ConnectorService` pure transforms: create / style / delete. Connectors carry no geometry and
/// take no part in the canvas z-order, so there is no sort-index numbering to pin here.
final class ConnectorServiceTests: XCTestCase {

    private var service: ConnectorService!

    override func setUp() {
        super.setUp()
        service = ConnectorService(repository: StubBoardRepository(), stickyService: StickyService(repository: StubBoardRepository()))
    }

    override func tearDown() {
        service = nil
        super.tearDown()
    }

    private func state(connectors: [Connector] = [], backgroundColorHex: String? = nil) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.connectors = connectors
        state.settings.global.backgroundColorHex = backgroundColorHex
        return state
    }

    private func endpoints() -> ConnectorEndpoints {
        ConnectorEndpoints(sourceStickyID: UUID(), sourceEdge: .right,
                           targetStickyID: UUID(), targetEdge: .left)
    }

    private func connector(style: ConnectorStyle = .default) -> Connector {
        Connector(cardID: UUID(), sourceStickyID: UUID(), sourceEdge: .top,
                  targetStickyID: UUID(), targetEdge: .bottom, style: style)
    }

    // MARK: - adding

    func testAdding_appendsConnectorWithEndpoints() throws {
        let ends = endpoints()

        let result = try service.adding(endpoints: ends, strokeColorHex: nil, toCardCanvas: UUID(), in: state())

        let added = result.connectors.first
        XCTAssertEqual(result.connectors.count, 1)
        XCTAssertEqual(added?.sourceStickyID, ends.sourceStickyID)
        XCTAssertEqual(added?.sourceEdge, .right)
        XCTAssertEqual(added?.targetEdge, .left)
    }

    func testAdding_noSpecifiedStroke_usesDefaultCapAndRouting() throws {
        let result = try service.adding(endpoints: endpoints(), strokeColorHex: nil,
                                        toCardCanvas: UUID(), in: state())
        XCTAssertEqual(result.connectors.first?.style.cap, ConnectorStyle.default.cap)
        XCTAssertEqual(result.connectors.first?.style.routing, ConnectorStyle.default.routing)
    }

    // MARK: - adding: unspecified-stroke auto-contrast against the canvas background

    func testAdding_noSpecifiedStroke_darkBackground_autoContrastsToOnDark() throws {
        let result = try service.adding(endpoints: endpoints(), strokeColorHex: nil,
                                        toCardCanvas: UUID(), in: state(backgroundColorHex: "1A1A1A"))
        XCTAssertEqual(result.connectors.first?.style.strokeColorHex, ContrastColor.onDarkHex)
    }

    func testAdding_noSpecifiedStroke_lightBackground_autoContrastsToOnLight() throws {
        let result = try service.adding(endpoints: endpoints(), strokeColorHex: nil,
                                        toCardCanvas: UUID(), in: state(backgroundColorHex: "FAFAFA"))
        XCTAssertEqual(result.connectors.first?.style.strokeColorHex, ContrastColor.onLightHex)
    }

    func testAdding_noSpecifiedStroke_noConfiguredBackground_leavesStrokeUnset() throws {
        let result = try service.adding(endpoints: endpoints(), strokeColorHex: nil,
                                        toCardCanvas: UUID(), in: state(backgroundColorHex: nil))
        // No explicit colour and no bakeable background ⇒ the stroke stays unset (nil), the
        // end-to-end signal Presentation resolves adaptively at draw time — not a `#000` sentinel.
        XCTAssertNil(result.connectors.first?.style.strokeColorHex)
    }

    func testAdding_specifiedStroke_darkBackground_keepsChosenColor() throws {
        let result = try service.adding(endpoints: endpoints(), strokeColorHex: "FF8800",
                                        toCardCanvas: UUID(), in: state(backgroundColorHex: "1A1A1A"))
        XCTAssertEqual(result.connectors.first?.style.strokeColorHex, "FF8800")
    }

    /// The robustification: gating on "specified-or-not" rather than sentinel equality means an
    /// explicitly-chosen pure black is honoured verbatim (stored as `"000000"`, distinct from the
    /// unset `nil`) — the old sentinel gate would have silently auto-contrasted it away.
    func testAdding_specifiedPureBlack_darkBackground_isNotAutoContrasted() throws {
        let result = try service.adding(endpoints: endpoints(),
                                        strokeColorHex: "000000",
                                        toCardCanvas: UUID(), in: state(backgroundColorHex: "1A1A1A"))
        XCTAssertEqual(result.connectors.first?.style.strokeColorHex, "000000")
    }

    /// The self-loop backstop: `adding` rejects a connector whose two endpoints are the same sticky,
    /// matching `reconnecting`'s rule (the UI grow gesture avoids this structurally; this guards the
    /// MCP `canvas_connector_add` path).
    func testAdding_sameSourceAndTargetSticky_throwsConnectorSelfLoop() {
        let stickyID = UUID()
        let selfLoop = ConnectorEndpoints(sourceStickyID: stickyID, sourceEdge: .right,
                                          targetStickyID: stickyID, targetEdge: .left)
        XCTAssertThrowsError(
            try service.adding(endpoints: selfLoop, strokeColorHex: nil, toCardCanvas: UUID(), in: state())
        ) { error in
            XCTAssertEqual(error as? ValidationError, .connectorSelfLoop)
        }
    }

    // MARK: - settings

    func testSettingCap_updatesCap() throws {
        let existing = connector()
        let result = try service.settingCap(id: existing.id, cap: .line, in: state(connectors: [existing]))
        XCTAssertEqual(result.connectors.first?.style.cap, .line)
    }

    func testSettingRouting_updatesRouting() throws {
        let existing = connector()
        let result = try service.settingRouting(id: existing.id, routing: .curve, in: state(connectors: [existing]))
        XCTAssertEqual(result.connectors.first?.style.routing, .curve)
    }

    func testSettingStrokeColor_updatesColor() throws {
        let existing = connector()
        let result = try service.settingStrokeColor(id: existing.id, colorHex: "ABCDEF",
                                                    in: state(connectors: [existing]))
        XCTAssertEqual(result.connectors.first?.style.strokeColorHex, "ABCDEF")
    }

    func testSettingStrokeWidth_clampsAboveMaximum() throws {
        let existing = connector()
        let result = try service.settingStrokeWidth(id: existing.id, width: 9_999,
                                                    in: state(connectors: [existing]))
        XCTAssertEqual(result.connectors.first?.style.strokeWidth, ConnectorStyle.maxStrokeWidth)
    }

    func testSettingWaypoint_setsOffset() throws {
        let existing = connector()
        let result = try service.settingWaypoint(id: existing.id, offset: CanvasOffset(dx: 7, dy: -9),
                                                 in: state(connectors: [existing]))
        XCTAssertEqual(result.connectors.first?.waypointOffset, CanvasOffset(dx: 7, dy: -9))
    }

    func testSettingWaypoint_nilClearsOffset() throws {
        var existing = connector()
        existing.waypointOffset = CanvasOffset(dx: 1, dy: 2)
        let result = try service.settingWaypoint(id: existing.id, offset: nil,
                                                 in: state(connectors: [existing]))
        XCTAssertNil(result.connectors.first?.waypointOffset)
    }

    func testSettingWaypoint_unknownID_throwsNotFound() {
        let missingID = UUID()
        XCTAssertThrowsError(
            try service.settingWaypoint(id: missingID, offset: .zero, in: state(connectors: [connector()]))
        ) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Connector", id: missingID))
        }
    }

    func testSettingCap_unknownID_throwsNotFound() {
        let existing = connector()
        let missingID = UUID()
        XCTAssertThrowsError(try service.settingCap(id: missingID, cap: .line, in: state(connectors: [existing]))) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Connector", id: missingID))
        }
    }

    // MARK: - reconnecting

    /// Builds a card with two stickies (`s1`, `s2`) and a connector `s1.right → s2.left`, plus a
    /// spare sticky `s3` on the same card, so reconnect targets exist. Returns the ids for assertions.
    private func reconnectFixture()
        -> (state: BoardState, connectorID: UUID, s1: UUID, s2: UUID, s3: UUID, cardID: UUID) {
        let cardID = UUID()
        let s1 = Sticky(cardID: cardID, content: "1", position: CanvasPosition(x: 0, y: 0), sortIndex: 0)
        let s2 = Sticky(cardID: cardID, content: "2", position: CanvasPosition(x: 100, y: 0), sortIndex: 1)
        let s3 = Sticky(cardID: cardID, content: "3", position: CanvasPosition(x: 200, y: 0), sortIndex: 2)
        let connector = Connector(cardID: cardID, sourceStickyID: s1.id, sourceEdge: .right,
                                  targetStickyID: s2.id, targetEdge: .left)
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [s1, s2, s3])
        state.connectors = [connector]
        return (state, connector.id, s1.id, s2.id, s3.id, cardID)
    }

    func testReconnecting_sourceOnly_movesSourceEndpoint() throws {
        let f = reconnectFixture()
        let result = try service.reconnecting(
            id: f.connectorID, source: ConnectorEndpoint(stickyID: f.s3, edge: .top), target: nil, in: f.state
        )
        let connector = result.connectors.first
        XCTAssertEqual(connector?.sourceStickyID, f.s3)
        XCTAssertEqual(connector?.sourceEdge, .top)
        // Target left untouched.
        XCTAssertEqual(connector?.targetStickyID, f.s2)
        XCTAssertEqual(connector?.targetEdge, .left)
    }

    func testReconnecting_targetOnly_movesTargetEndpoint() throws {
        let f = reconnectFixture()
        let result = try service.reconnecting(
            id: f.connectorID, source: nil, target: ConnectorEndpoint(stickyID: f.s3, edge: .bottom), in: f.state
        )
        let connector = result.connectors.first
        XCTAssertEqual(connector?.targetStickyID, f.s3)
        XCTAssertEqual(connector?.targetEdge, .bottom)
        XCTAssertEqual(connector?.sourceStickyID, f.s1)
        XCTAssertEqual(connector?.sourceEdge, .right)
    }

    func testReconnecting_sameStickyNewEdge_changesOnlyEdge() throws {
        let f = reconnectFixture()
        // Move the source end to a different edge of the SAME sticky — allowed, not a self-loop.
        let result = try service.reconnecting(
            id: f.connectorID, source: ConnectorEndpoint(stickyID: f.s1, edge: .top), target: nil, in: f.state
        )
        XCTAssertEqual(result.connectors.first?.sourceStickyID, f.s1)
        XCTAssertEqual(result.connectors.first?.sourceEdge, .top)
    }

    func testReconnecting_unknownConnector_throwsNotFound() {
        let f = reconnectFixture()
        let missing = UUID()
        XCTAssertThrowsError(try service.reconnecting(
            id: missing, source: ConnectorEndpoint(stickyID: f.s3, edge: .top), target: nil, in: f.state
        )) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Connector", id: missing))
        }
    }

    func testReconnecting_unknownSticky_throwsNotFound() {
        let f = reconnectFixture()
        let missing = UUID()
        XCTAssertThrowsError(try service.reconnecting(
            id: f.connectorID, source: ConnectorEndpoint(stickyID: missing, edge: .top), target: nil, in: f.state
        )) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Sticky", id: missing))
        }
    }

    func testReconnecting_resultingSelfLoop_throwsConnectorSelfLoop() {
        let f = reconnectFixture()
        // Moving the source end onto the target sticky would make both ends the same sticky.
        XCTAssertThrowsError(try service.reconnecting(
            id: f.connectorID, source: ConnectorEndpoint(stickyID: f.s2, edge: .top), target: nil, in: f.state
        )) { error in
            XCTAssertEqual(error as? ValidationError, .connectorSelfLoop)
        }
    }

    // MARK: - deleting

    func testDeleting_removesOnlyTheTarget() throws {
        let keep = connector()
        let drop = connector()
        let result = try service.deleting(id: drop.id, from: state(connectors: [keep, drop]))
        XCTAssertEqual(result.connectors.map(\.id), [keep.id])
    }

    func testDeleting_unknownID_throwsNotFound() {
        let missingID = UUID()
        XCTAssertThrowsError(try service.deleting(id: missingID, from: state(connectors: []))) { error in
            XCTAssertEqual(error as? OperationError, .notFound(entityKind: "Connector", id: missingID))
        }
    }
}
