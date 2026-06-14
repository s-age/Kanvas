import Foundation

enum CardSchedule: Sendable, Equatable {
    case deadline(Date)
    case period(start: Date, end: Date)
}
