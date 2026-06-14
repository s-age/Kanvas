import Foundation

/// A single drawable on the canvas — a sticky, a shape, or an image — unified so z-order,
/// hit-testing, drag, and resize treat all kinds the same. They share one `sortIndex` space, so the
/// canvas merges them into a `[CanvasItem]` sorted by `sortIndex` and works against that. Geometry
/// accessors are common; kind-specific rendering (text/labels vs stroke/fill vs bitmap) and
/// behaviour (text-edit, labels, copy — stickies only) branch on the payload.
enum CanvasItem: Equatable {
    case sticky(StickyResponse)
    case shape(ShapeResponse)
    case image(ImageResponse)
    case text(TextResponse)

    var id: UUID {
        switch self {
        case .sticky(let s): s.id
        case .shape(let s): s.id
        case .image(let i): i.id
        case .text(let t): t.id
        }
    }

    var sortIndex: Int {
        switch self {
        case .sticky(let s): s.sortIndex
        case .shape(let s): s.sortIndex
        case .image(let i): i.sortIndex
        case .text(let t): t.sortIndex
        }
    }

    /// Centre x (the model anchors stickies, shapes, images, and texts by their centre).
    var centerX: Double {
        switch self {
        case .sticky(let s): s.positionX
        case .shape(let s): s.positionX
        case .image(let i): i.positionX
        case .text(let t): t.positionX
        }
    }

    var centerY: Double {
        switch self {
        case .sticky(let s): s.positionY
        case .shape(let s): s.positionY
        case .image(let i): i.positionY
        case .text(let t): t.positionY
        }
    }

    var width: Double {
        switch self {
        case .sticky(let s): s.width
        case .shape(let s): s.width
        case .image(let i): i.width
        case .text(let t): t.width
        }
    }

    var height: Double {
        switch self {
        case .sticky(let s): s.height
        case .shape(let s): s.height
        case .image(let i): i.height
        case .text(let t): t.height
        }
    }

    var minWidth: Double {
        switch self {
        case .sticky(let s): s.minWidth
        case .shape(let s): s.minWidth
        case .image(let i): i.minWidth
        case .text(let t): t.minWidth
        }
    }

    var minHeight: Double {
        switch self {
        case .sticky(let s): s.minHeight
        case .shape(let s): s.minHeight
        case .image(let i): i.minHeight
        case .text(let t): t.minHeight
        }
    }

    var maxWidth: Double {
        switch self {
        case .sticky(let s): s.maxWidth
        case .shape(let s): s.maxWidth
        case .image(let i): i.maxWidth
        case .text(let t): t.maxWidth
        }
    }

    var maxHeight: Double {
        switch self {
        case .sticky(let s): s.maxHeight
        case .shape(let s): s.maxHeight
        case .image(let i): i.maxHeight
        case .text(let t): t.maxHeight
        }
    }

    var isSticky: Bool {
        if case .sticky = self { return true }
        return false
    }

    /// The text payload when this item is a free-text object, else `nil` (text-edit is text/sticky).
    var textValue: TextResponse? {
        if case .text(let t) = self { return t }
        return nil
    }

    /// The sticky payload when this item is a sticky, else `nil` (hover/label/edit are sticky-only).
    var stickyValue: StickyResponse? {
        if case .sticky(let s) = self { return s }
        return nil
    }

    /// The image payload when this item is an image, else `nil`.
    var imageValue: ImageResponse? {
        if case .image(let i) = self { return i }
        return nil
    }

    /// The source aspect ratio when this item is an image (used to lock the resize preview to the
    /// image's true shape), else `nil`.
    var aspectRatioIfImage: Double? {
        if case .image(let i) = self { return i.aspectRatio }
        return nil
    }
}
