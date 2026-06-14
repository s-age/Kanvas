import Foundation

/// How deep the per-board undo ring goes. "How many mutations back the user can step" is a product
/// decision (domain policy), not a storage detail — so the value has a Domain home rather than being
/// a hard-coded constant inside the Repository. The Repository is *told* this depth and only applies
/// the ring bound (the trimming mechanism); it never picks the number.
///
/// Today the value is a fixed default injected via DI. It lives here as the injection point so a
/// later ticket can surface it on `GlobalSettings` / `BoardSettings` (user-configurable depth)
/// without the number having to migrate out of the Repository at that point.
struct UndoPolicy: Sendable, Equatable {
    /// Maximum number of reversible mutations retained per board.
    var maxDepth: Int

    init(maxDepth: Int) {
        self.maxDepth = maxDepth
    }

    static let `default` = UndoPolicy(maxDepth: 5)
}
