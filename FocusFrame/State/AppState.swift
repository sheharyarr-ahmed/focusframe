import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppState {
    let sessionManager: SessionManager

    init(modelContext: ModelContext) {
        self.sessionManager = SessionManager(modelContext: modelContext)
    }
}
