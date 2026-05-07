import Foundation
import SwiftData

@Model
final class Insight {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var text: String
    var model: String
    var generatedAt: Date
    var status: String

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        text: String = "",
        model: String,
        generatedAt: Date = .now,
        status: String = "pending"
    ) {
        self.id = id
        self.sessionID = sessionID
        self.text = text
        self.model = model
        self.generatedAt = generatedAt
        self.status = status
    }
}

extension Insight {
    enum Status: String {
        case pending, succeeded, failed
    }

    var statusEnum: Status { Status(rawValue: status) ?? .pending }
}
