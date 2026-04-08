import Foundation

@MainActor
@Observable
final class FanControlLogger {
    struct Entry: Identifiable, Sendable {
        let id: UUID
        let timestamp: Date
        let level: Level
        let message: String

        init(timestamp: Date = .now, level: Level, message: String) {
            self.id = UUID()
            self.timestamp = timestamp
            self.level = level
            self.message = message
        }
    }

    enum Level: String, Sendable {
        case info
        case warning
        case error
    }

    private let fileURL: URL
    private let maximumEntries: Int

    var entries: [Entry]

    init(
        fileURL: URL = FileManager.default.temporaryDirectory.appending(path: "mfc-runtime.log"),
        maximumEntries: Int = 200
    ) {
        self.fileURL = fileURL
        self.maximumEntries = maximumEntries
        self.entries = []
    }

    func info(_ message: String) {
        append(level: .info, message: message)
    }

    func warning(_ message: String) {
        append(level: .warning, message: message)
    }

    func error(_ message: String) {
        append(level: .error, message: message)
    }

    private func append(level: Level, message: String) {
        let entry = Entry(level: level, message: message)
        entries.insert(entry, at: 0)
        if entries.count > maximumEntries {
            entries.removeLast(entries.count - maximumEntries)
        }

        let line = "[\(entry.timestamp.ISO8601Format())] [\(level.rawValue.uppercased())] \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    try? handle.seekToEnd()
                    try? handle.write(contentsOf: data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: fileURL)
            }
        }
    }
}
