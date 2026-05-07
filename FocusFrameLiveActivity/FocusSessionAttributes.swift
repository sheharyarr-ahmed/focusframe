import ActivityKit
import Foundation

struct FocusSessionAttributes: ActivityAttributes {
    public typealias FocusSessionState = ContentState

    public struct ContentState: Codable, Hashable {
        var elapsedSeconds: Int
        var distractionCount: Int
        var isPaused: Bool
    }

    let sessionID: UUID
    let goalText: String
    let startedAt: Date
    let plannedDurationMinutes: Int?
}
