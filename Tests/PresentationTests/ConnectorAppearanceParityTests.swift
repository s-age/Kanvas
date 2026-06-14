import XCTest
@testable import KanvasCore

/// Presentation cannot import `Domain`, so the connector adaptive-contrast pair is re-declared as
/// literals in `ConnectorAppearance`. These tests pin that mirror to the authoritative Domain values
/// (`ContrastColor`) so a future change to one side that forgets the other fails loudly here —
/// preventing a silent drift that would leave the draw-time auto-contrast keying off the wrong hex.
/// (The "unset" signal is now the Optional stroke being `nil`, not a mirrored sentinel — so there is
/// no longer a default-stroke value to pin; see `ConnectorStrokeColorGateTests`.)
final class ConnectorAppearanceParityTests: XCTestCase {

    func testOnLightStrokeMirrorsDomainContrast() {
        XCTAssertEqual(ConnectorAppearance.onLightStrokeHex, ContrastColor.onLightHex)
    }

    func testOnDarkStrokeMirrorsDomainContrast() {
        XCTAssertEqual(ConnectorAppearance.onDarkStrokeHex, ContrastColor.onDarkHex)
    }
}
