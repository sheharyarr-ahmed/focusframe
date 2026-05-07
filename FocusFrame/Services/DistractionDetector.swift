import Foundation
import Observation
import OSLog

@Observable
@MainActor
final class DistractionDetector {
    enum Phase {
        case active, inactive, background
    }

    private(set) var distractionCount: Int = 0
    private var isObserving: Bool = false

    var onDistractionCountChanged: (() -> Void)?

    func sessionStarted() {
        distractionCount = 0
        isObserving = true
        Logger.distraction.info("detector armed")
    }

    func sessionEnded() {
        isObserving = false
        Logger.distraction.info("detector disarmed final=\(self.distractionCount, privacy: .public)")
    }

    func handleScenePhaseChange(_ phase: Phase) {
        guard isObserving, phase == .background else { return }
        distractionCount += 1
        Logger.distraction.info("distraction count=\(self.distractionCount, privacy: .public)")
        onDistractionCountChanged?()
    }
}
