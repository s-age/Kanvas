import Foundation

struct Board: Sendable, Identifiable, Equatable {
    let id: UUID
    var title: String

    init(id: UUID = UUID(), title: String) {
        self.id = id
        self.title = title
    }
}
