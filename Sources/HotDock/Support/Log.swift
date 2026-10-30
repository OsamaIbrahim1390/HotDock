import Foundation

/// Appends to a plain-text log in Application Support, alongside NSLog.
///
/// NSLog alone is awkward here: when the app is launched from Finder or `open`, stderr goes to
/// the unified log where it is hard to retrieve. A file we own is trivial to read after
/// reproducing a problem, and it stays local like everything else this app writes.
enum Log {
    private static let queue = DispatchQueue(label: "com.hotdock.HotDock.log")
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        // POSIX locale, or a 12-hour region turns "16:46" into "4:46 PM".
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    static var fileURL: URL { AppPaths.support.appendingPathComponent("hotdock.log") }

    /// Caps the file so a long-running session cannot grow it without bound.
    private static let maxBytes = 512 * 1024

    static func write(_ message: String) {
        NSLog("HotDock: \(message)")
        let line = "\(formatter.string(from: Date()))  \(message)\n"
        queue.async {
            guard AppPaths.ensure(AppPaths.support) != nil,
                  let data = line.data(using: .utf8) else { return }
            let url = fileURL
            let fm = FileManager.default
            if !fm.fileExists(atPath: url.path) {
                try? data.write(to: url)
                return
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                if (try? handle.seekToEnd()).map({ $0 > UInt64(maxBytes) }) == true {
                    try? handle.truncate(atOffset: 0)
                }
                try? handle.write(contentsOf: data)
            }
        }
    }

    /// Logs only when the message differs from the previous one with the same key, so a
    /// repeating poll does not fill the file with identical lines.
    private static var lastByKey: [String: String] = [:]
    static func writeIfChanged(key: String, _ message: String) {
        var shouldWrite = false
        queue.sync {
            if lastByKey[key] != message {
                lastByKey[key] = message
                shouldWrite = true
            }
        }
        if shouldWrite { write(message) }
    }
}
