import Foundation

/// UseCase-layer schedule input carried by `EditCardRequest.schedule`.
///
/// Mirrors the Domain `CardSchedule` shape but keeps Request construction free of any
/// Domain-entity name: Presentation (`CardMetadataEditor.buildSchedule`) and the MCP gateway
/// (`KanvasMCPGateway.scheduleValue`) build this, and `toDomain` — the single Request→Domain
/// crossing — stays internal to the UseCase layer (never called from Presentation).
enum ScheduleInput: Sendable, Equatable {
    case deadline(Date)
    case period(start: Date, end: Date)

    var toDomain: CardSchedule {
        switch self {
        case .deadline(let date): .deadline(date)
        case .period(let start, let end): .period(start: start, end: end)
        }
    }
}
