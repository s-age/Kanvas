import XCTest
@testable import KanvasCore

/// `BoardSnapshotMapper` / `ImageDTO` must round-trip canvas images **and** keep decoding snapshots
/// that store the asset reference under the original JSON key `imageID`. The Swift property was
/// renamed to `assetID`; the persisted key intentionally stayed `imageID` (renaming it once
/// corrupted real boards — "Board data file is corrupted"). These pin both directions.
final class BoardSnapshotMapperImageTests: XCTestCase {

    private func state(with image: CanvasImage) -> BoardState {
        var state = BoardState(board: Board(title: "B"), columns: [], cards: [], stickies: [])
        state.images = [image]
        return state
    }

    private func image(assetID: UUID) -> CanvasImage {
        CanvasImage(cardID: UUID(), assetID: assetID, position: CanvasPosition(x: 1, y: 2),
                    size: ImageSize(width: 120, height: 80), aspectRatio: 1.5, sortIndex: 0)
    }

    func testRoundTrip_preservesAssetID() {
        let assetID = UUID()
        let restored = BoardSnapshotMapper.decodeIgnoringRecoveries(
            BoardSnapshotMapper.toDTO(state(with: image(assetID: assetID)))
        )

        XCTAssertEqual(restored.images.first?.assetID, assetID)
    }

    func testEncode_writesTheAssetReferenceUnderTheLegacyImageIDKey() throws {
        let dto = BoardSnapshotMapper.toDTO(state(with: image(assetID: UUID())))
        let data = try JSONEncoder().encode(dto)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let images = try XCTUnwrap(json["images"] as? [[String: Any]])

        // The on-disk key must stay `imageID` (not `assetID`) so older snapshots keep loading.
        XCTAssertNotNil(images.first?["imageID"])
    }

    func testDecode_legacySnapshotWithImageIDKey_recoversTheImage() throws {
        // A board saved by the first shipped build: the asset reference is keyed `imageID`.
        let cardID = UUID().uuidString
        let assetID = UUID().uuidString
        let json = """
        {
          "board": { "id": "\(UUID().uuidString)", "title": "Kanvas" },
          "columns": [], "cards": [], "stickies": [],
          "images": [{
            "id": "\(UUID().uuidString)", "cardID": "\(cardID)", "imageID": "\(assetID)",
            "positionX": 10, "positionY": 20, "width": 120, "height": 80,
            "aspectRatio": 1.5, "sortIndex": 0
          }]
        }
        """
        let dto = try JSONDecoder().decode(BoardSnapshotDTO.self, from: Data(json.utf8))
        let state = BoardSnapshotMapper.decodeIgnoringRecoveries(dto)

        XCTAssertEqual(state.images.first?.assetID.uuidString, assetID)
    }
}
