import Foundation

/// Grows a connector from `sourceStickyID`'s `sourceEdge`. The target is either an existing sticky
/// (`existingTargetStickyID != nil`, "drop on a sticky") or a brand-new sticky created at the drop
/// point (`existingTargetStickyID == nil`, "drop on empty"). `sourceEdge` / `targetEdge` cross the
/// boundary as `CanvasEdge` raw values (Presentation never imports the domain enum).
struct AddConnectorRequest: ValidatableRequest {
    let cardID: UUID
    let sourceStickyID: UUID
    let sourceEdge: String
    let targetEdge: String
    /// Non-nil ⇒ link to this existing sticky. Nil ⇒ create a new sticky at the placement below.
    let existingTargetStickyID: UUID?
    /// New-sticky placement (centre + size), used only when `existingTargetStickyID == nil`.
    let newStickyX: Double
    let newStickyY: Double
    let newStickyWidth: Double
    let newStickyHeight: Double
    /// Explicit stroke colour `RRGGBB`, or nil to inherit the canvas-contrasting default. Nil from
    /// the app's grow gesture (no create-time colour chooser); set from the MCP `canvas_connector_add`
    /// tool. The domain gates auto-contrast on this being *absent*, not on a sentinel value — so an
    /// explicit colour is never silently overwritten.
    let strokeColorHex: String?

    init(cardID: UUID, sourceStickyID: UUID, sourceEdge: String, targetEdge: String,
         existingTargetStickyID: UUID?,
         newStickyX: Double, newStickyY: Double, newStickyWidth: Double, newStickyHeight: Double,
         strokeColorHex: String? = nil) {
        self.cardID = cardID
        self.sourceStickyID = sourceStickyID
        self.sourceEdge = sourceEdge
        self.targetEdge = targetEdge
        self.existingTargetStickyID = existingTargetStickyID
        self.newStickyX = newStickyX
        self.newStickyY = newStickyY
        self.newStickyWidth = newStickyWidth
        self.newStickyHeight = newStickyHeight
        self.strokeColorHex = strokeColorHex
    }

    func validate() throws {
        guard CanvasEdge(rawValue: sourceEdge) != nil, CanvasEdge(rawValue: targetEdge) != nil else {
            throw ValidationError.invalidConnectorEdge
        }
        if let strokeColorHex {
            try LabelValidation.validate(colorHex: strokeColorHex)
        }
    }
}
