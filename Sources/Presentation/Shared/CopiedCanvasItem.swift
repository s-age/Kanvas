import Foundation

/// The single ⌘C paste buffer entry — a copied sticky **or** a copied text, never both. Modelling
/// the buffer as one optional sum type makes the invalid "both set" state unrepresentable, unlike
/// the parallel optionals it replaced (which only each copy site kept mutually exclusive by hand).
/// Mirrors the `CanvasSelection` precedent: each case carries its kind, so a single optional cannot
/// disagree with itself.
enum CopiedCanvasItem: Equatable {
    case sticky(UUID)
    case text(UUID)

    var stickyID: UUID? {
        if case .sticky(let id) = self { return id }
        return nil
    }

    var textID: UUID? {
        if case .text(let id) = self { return id }
        return nil
    }
}
