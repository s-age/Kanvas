import Foundation

enum OperationError: LocalizedError, Equatable, Sendable {
    case notFound(entityKind: String, id: UUID)
    case loadFailed
    case saveFailed
    case fileCorrupted
    /// A "should be impossible" invariant was violated mid-operation — surfaced loudly rather than
    /// swallowed, so a latent logic bug is observed instead of silently dropping the action.
    case inconsistentState(reason: String)

    var errorDescription: String? {
        switch self {
        case .notFound(let kind, let id): "\(kind) not found: \(id)"
        case .loadFailed: "Failed to load board data."
        case .saveFailed: "Failed to save board data."
        case .fileCorrupted: "Board data file is corrupted."
        case .inconsistentState(let reason): "Inconsistent state: \(reason)"
        }
    }
}
