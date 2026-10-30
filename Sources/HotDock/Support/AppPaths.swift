import Foundation

/// Every file HotDock writes lives under Application Support, on this Mac only.
/// Nothing here is in iCloud Drive, Documents, or any synced location.
enum AppPaths {
    static let folderName = "HotDock"

    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(folderName, isDirectory: true)
    }

    static var scripts: URL { support.appendingPathComponent("Scripts", isDirectory: true) }
    static var notes: URL { support.appendingPathComponent("Notes", isDirectory: true) }

    /// Creates the directory if needed and returns it. Returns nil only if the filesystem refuses,
    /// which we surface to the user rather than crashing.
    @discardableResult
    static func ensure(_ url: URL) -> URL? {
        do {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        } catch {
            NSLog("HotDock: could not create \(url.path): \(error.localizedDescription)")
            return nil
        }
    }
}
