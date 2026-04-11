import Foundation

enum DebugLog {
    private static let logURL = URL(fileURLWithPath: "/tmp/voice2input.log")

    static func write(_ message: String) {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        let data = Data(line.utf8)

        if FileManager.default.fileExists(atPath: logURL.path) {
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                return
            }
        }

        try? data.write(to: logURL, options: .atomic)
    }
}
