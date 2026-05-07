import Foundation
import Observation
import SwiftData

@Observable
@MainActor
final class AppState {
    let keychainService: KeychainService
    let claudeService: ClaudeService
    let distractionDetector: DistractionDetector
    let sessionManager: SessionManager

    init(modelContext: ModelContext) {
        let keychain = KeychainService()
        let claude = ClaudeService(keychainService: keychain)
        let detector = DistractionDetector()
        let session = SessionManager(
            modelContext: modelContext,
            claudeService: claude,
            distractionDetector: detector
        )
        self.keychainService = keychain
        self.claudeService = claude
        self.distractionDetector = detector
        self.sessionManager = session

        detector.onDistractionCountChanged = { [weak session] in
            session?.handleDistractionUpdate()
        }
    }
}
