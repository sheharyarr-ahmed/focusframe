import Foundation
import SwiftData

@Model
final class Goal {
    @Attribute(.unique) var id: UUID
    var text: String
    var createdAt: Date
    var lastUsedAt: Date
    var useCount: Int

    init(
        id: UUID = UUID(),
        text: String,
        createdAt: Date = .now,
        lastUsedAt: Date = .now,
        useCount: Int = 1
    ) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
        self.useCount = useCount
    }
}
