import Foundation

/// The slice of `BoardViewModel` the settings window needs: list the boards, know which one is
/// active, and apply an updated board back after a save. (Settings are loaded fresh per scope via
/// `LoadBoardByIDUseCaseImpl` / `LoadBoardTemplateUseCaseImpl`, so the host no longer exposes the active
/// board's content.) `SettingsViewModel` depends on this protocol rather than the concrete
/// `BoardViewModel` so it is unit-testable without constructing the full board VM (which wires ~50
/// use cases). `BoardViewModel` is the only production conformer.
@MainActor
protocol BoardSettingsHost: AnyObject {
    /// Every board (id + title) in display order — the settings sidebar lists these alongside
    /// "Default" so any board's settings / column colours can be edited.
    var boards: [BoardSummary] { get }
    /// Which board the canvas is currently showing. A settings edit to this board is applied back
    /// via `applyBoard`; edits to any other board are persisted only.
    var activeBoardID: UUID? { get }
    func applyBoard(_ response: BoardResponse)
}

extension BoardViewModel: BoardSettingsHost {}
