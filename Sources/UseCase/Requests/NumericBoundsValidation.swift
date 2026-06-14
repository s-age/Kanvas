import Foundation

/// Shared bounds validation for the numeric setter requests (stroke width, font size) plus the raw
/// canvas coordinate / offset finiteness guard. The Request layer is the validation boundary. Each
/// *bounded* field's Domain entity initializer clamps it to `[min, max]` on load (untrusted JSON
/// re-validation); these helpers gate the *write* path so a boundary-less MCP caller is rejected with
/// an explicit `ValidationError` instead of silently clamped. Positions/offsets are the exception —
/// they are clamped *nowhere* — so their finiteness is enforced only here (see `finiteCoordinates`).
///
/// `ClosedRange.contains` also rejects non-finite input for free — `NaN`/`Inf` are not contained — so
/// no separate `.isFinite` check is needed. Bounds are passed in from the owning entity
/// (`ConnectorStyle`/`CanvasShapeStyle.minStrokeWidth…max`, `StickyTextStyle.minFontSize…max`) so the
/// valid range keeps a single source of truth per concept.
enum NumericBoundsValidation {
    static func validate(strokeWidth: Double, in bounds: ClosedRange<Double>) throws {
        guard bounds.contains(strokeWidth) else {
            throw ValidationError.strokeWidthOutOfRange(min: bounds.lowerBound, max: bounds.upperBound)
        }
    }

    static func validate(fontSize: Double, in bounds: ClosedRange<Double>) throws {
        guard bounds.contains(fontSize) else {
            throw ValidationError.fontSizeOutOfRange(min: bounds.lowerBound, max: bounds.upperBound)
        }
    }

    /// Rejects a raw canvas coordinate / offset component that is not finite (`NaN`/`±Inf`). Unlike
    /// size and the numeric setters above, positions and offsets are **never** clamped on the entity
    /// `init` path — they flow straight into `CanvasPosition`/`CanvasOffset` — so a boundary-less MCP
    /// caller (`canvas_sticky_move` etc.) could otherwise persist `NaN`/`Inf` into the whole-blob
    /// store and corrupt every downstream draw pass. The check is per-component and variadic so a
    /// Request can gate all of its coordinate fields in one call (ticket 4FD6D166).
    ///
    /// Scope is finiteness only: a magnitude bound is intentionally omitted (it has no single
    /// source of truth — the canvas is unbounded — and the entity layer never clamps it). The
    /// `nil`-tolerant overload is for the optional connector waypoint offset.
    static func validate(finiteCoordinates coordinates: Double...) throws {
        try validate(finiteCoordinates: coordinates)
    }

    static func validate(finiteCoordinates coordinates: [Double]) throws {
        guard coordinates.allSatisfy(\.isFinite) else {
            throw ValidationError.nonFiniteCoordinate
        }
    }

    /// Optional-tolerant variant: a `nil` component is "absent", not "non-finite", and passes. Any
    /// present component must be finite.
    static func validate(finiteCoordinates coordinates: Double?...) throws {
        guard coordinates.compactMap({ $0 }).allSatisfy(\.isFinite) else {
            throw ValidationError.nonFiniteCoordinate
        }
    }
}
