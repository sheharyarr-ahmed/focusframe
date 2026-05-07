import Foundation
import SwiftData

@Model
final class Insight {
    @Attribute(.unique) var id: UUID
    var sessionID: UUID
    var text: String
    var model: String
    var generatedAt: Date

    init(
        id: UUID = UUID(),
        sessionID: UUID,
        text: String,
        model: String,
        generatedAt: Date = .now
    ) {
        self.id = id
        self.sessionID = sessionID
        self.text = text
        self.model = model
        self.generatedAt = generatedAt
    }
}
