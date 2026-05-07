import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppState {
    let keychainService: KeychainService
    let claudeService: ClaudeService
    let sessionManager: SessionManager

    init(modelContext: ModelContext) {
        let keychain = KeychainService()
        let claude = ClaudeService(keychainService: keychain)
        self.keychainService = keychain
        self.claudeService = claude
        self.sessionManager = SessionManager(
            modelContext: modelContext,
            claudeService: claude
        )
    }
}
