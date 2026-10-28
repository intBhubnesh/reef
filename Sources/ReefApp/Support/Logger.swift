import Foundation

/// JSON-lines log at ~/Library/Logs/Reef/reef.log: {"t","l","c","m","d"}.
enum Log {
    private static let queue = DispatchQueue(label: "app.reef.log")
    private static let formatter = ISO8601DateFormatter()
    private static let maxBytes = 5_000_000

    static func info(_ category: String, _ message: String, _ details: [String: String]? = nil) {
        write(level: "info", category: category, message: message, details: details)
    }

    static func warn(_ category: String, _ message: String, _ details: [String: String]? = nil) {
        write(level: "warn", category: category, message: message, details: details)
    }

    private static func write(level: String, category: String, message: String, details: [String: String]?) {
        var record: [String: Any] = ["t": formatter.string(from: Date()), "l": level, "c": category, "m": message]
        if let details { record["d"] = details }
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        queue.async {
            let path = Paths.logFile.path
            if let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int, size > maxBytes {
                try? FileManager.default.removeItem(atPath: path + ".1")
                try? FileManager.default.moveItem(atPath: path, toPath: path + ".1")
            }
            if let handle = FileHandle(forWritingAtPath: path) {
                handle.seekToEndOfFile(); handle.write(data); handle.closeFile()
            } else {
                FileManager.default.createFile(atPath: path, contents: data)
            }
        }
    }
}
