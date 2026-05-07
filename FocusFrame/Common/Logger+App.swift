import OSLog

extension Logger {
    private static let subsystem = "com.sheryahmed.focusframe"

    static let session = Logger(subsystem: subsystem, category: "session")
    static let claude = Logger(subsystem: subsystem, category: "claude")
    static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
