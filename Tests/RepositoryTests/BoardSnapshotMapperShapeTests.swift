import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper` must round-trip shapes — including the **no-fill** state (`fillColorHex
/// == nil`), which the explicit `hasFill` flag keeps distinguishable from an old snapshot missing
/// the field — and must decode shape-less snapshots into an empty collection. Back-compat for
/// snapshots lacking a `topology` field is also covered: the field is inferred from `kind`.
final class BoardSnapshotMapperShapeTests: XCTestCase {

    private func shape(kind: String, topology: ShapeTopology = .box,
                       style: CanvasShapeStyle, lineRising: Bool = false) -> CanvasShape {
        CanvasShape(cardID: UUID(), kind: kind, topology: topology,
                    position: CanvasPosition(x: 1, y: 2),
                    size: ShapeSize(width: 100, height: 80), style: style,
                    lineRising: lineRising, sortIndex: 0)
    }

    private func state(with shape: CanvasShape) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.shapes = [shape]
        return state
    }

    func testRoundTrip_preservesKind() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "line", topology: .segment, style: .default)))
        )

        XCTAssertEqual(restored.shapes.first?.kind, "line")
    }

    func testRoundTrip_preservesTopology_box() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "rectangle", topology: .box, style: .default)))
        )

        XCTAssertEqual(restored.shapes.first?.topology, .box)
    }

    func testRoundTrip_preservesTopology_segment() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "line", topology: .segment, style: .default)))
        )

        XCTAssertEqual(restored.shapes.first?.topology, .segment)
    }

    func testRoundTrip_preservesStrokeColorAndWidth() {
        let style = CanvasShapeStyle(strokeColorHex: "112233", fillColorHex: nil, strokeWidth: 7)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "rectangle", style: style)))
        )

        XCTAssertEqual(restored.shapes.first?.style.strokeWidth, 7)
    }

    func testRoundTrip_preservesNoFill() {
        let style = CanvasShapeStyle(strokeColorHex: "000000", fillColorHex: nil, strokeWidth: 2)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "rectangle", style: style)))
        )

        XCTAssertNil(restored.shapes.first?.style.fillColorHex)
    }

    func testRoundTrip_preservesFillColor() {
        let style = CanvasShapeStyle(strokeColorHex: "000000", fillColorHex: "ABCDEF", strokeWidth: 2)
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "ellipse", style: style)))
        )

        XCTAssertEqual(restored.shapes.first?.style.fillColorHex, "ABCDEF")
    }

    func testRoundTrip_preservesLineRising() {
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: shape(kind: "line", topology: .segment,
                                                        style: .default, lineRising: true)))
        )

        XCTAssertEqual(restored.shapes.first?.lineRising, true)
    }

    // MARK: - Back-compat: absent `topology` field inferred from `kind`

    func testToEntities_legacyShapeWithoutLineRising_decodesToFalse() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [],
            shapes: [ShapeDTO(
                id: UUID(), cardID: UUID(), kind: "line", positionX: 0, positionY: 0,
                width: 100, height: 80, strokeColorHex: nil, strokeWidth: nil,
                fillColorHex: nil, hasFill: nil, lineRising: nil, sortIndex: 0
            )],
            labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.shapes.first?.lineRising, false)
    }

    func testToEntities_absentGeometry_lineKind_inferredAsSegment() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [],
            shapes: [ShapeDTO(
                id: UUID(), cardID: UUID(), kind: "line", positionX: 0, positionY: 0,
                width: 100, height: 80, strokeColorHex: nil, strokeWidth: nil,
                fillColorHex: nil, hasFill: nil, lineRising: nil, sortIndex: 0
            )],
            labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.shapes.first?.topology, .segment)
    }

    func testToEntities_absentGeometry_rectangleKind_inferredAsBox() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [],
            shapes: [ShapeDTO(
                id: UUID(), cardID: UUID(), kind: "rectangle", positionX: 0, positionY: 0,
                width: 100, height: 80, strokeColorHex: nil, strokeWidth: nil,
                fillColorHex: nil, hasFill: nil, lineRising: nil, sortIndex: 0
            )],
            labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.shapes.first?.topology, .box)
    }

    func testToEntities_explicitTopologyField_winsOverKindInference() {
        // A DTO whose `kind` would infer `.box` but whose explicit `topology` field says "segment"
        // must decode to `.segment` (entity topology field) — the stored DTO field wins.
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [],
            shapes: [ShapeDTO(
                id: UUID(), cardID: UUID(), kind: "rectangle", topology: "segment",
                positionX: 0, positionY: 0,
                width: 100, height: 80, strokeColorHex: nil, strokeWidth: nil,
                fillColorHex: nil, hasFill: nil, lineRising: nil, sortIndex: 0
            )],
            labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.shapes.first?.topology, .segment)
    }

    func testToEntities_legacySnapshotWithoutShapes_decodesToEmpty() {
        let dto = BoardSnapshotDTO(
            board: BoardDTO(id: UUID(), title: "B"), columns: [], cards: [],
            stickies: [], shapes: nil, labels: nil
        )

        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertTrue(state.shapes.isEmpty)
    }
}
