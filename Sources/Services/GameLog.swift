import Foundation

/// Simple file logger — writes to ~/Desktop/GameTranslator.log
/// so we can always read the output regardless of Xcode console
enum GameLog {
    /// Set by default so messages logged before setup() (e.g. a duplicate
    /// launch quitting early) still reach the file
    private static var logFileURL: URL? = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop")
        .appendingPathComponent("GameTranslator.log")
    private static let dateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss.SSS"
        return df
    }()

    static func setup() {
        let desktop = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop")
            .appendingPathComponent("GameTranslator.log")
        logFileURL = desktop

        // Clear previous log
        try? "".write(to: desktop, atomically: true, encoding: .utf8)
    }

    static func log(_ message: String) {
        let timestamp = dateFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)\n"

        // Print to stdout (Xcode console)
        NSLog("[GameTranslator] %@", message)

        // Also write to file
        if let url = logFileURL {
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                if let data = line.data(using: .utf8) {
                    handle.write(data)
                }
                handle.closeFile()
            } else {
                try? line.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}
