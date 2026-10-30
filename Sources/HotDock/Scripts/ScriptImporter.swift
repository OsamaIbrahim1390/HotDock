import AppKit
import UniformTypeIdentifiers

/// Brings scripts in from outside: a text file on disk, or a note in the Notes app.
///
/// Nothing here touches the network. The file path is whatever you pick in the open panel,
/// and the Notes path is an Apple Event to the Notes app running on this Mac — the same
/// mechanism as the Spotify controls, and it asks for permission the first time you use it
/// rather than at launch.
enum ScriptImporter {

    enum ImportError: LocalizedError {
        case notesNotInstalled
        case permissionDenied
        case scriptFailed(String)
        case unreadable(String)

        var errorDescription: String? {
            switch self {
            case .notesNotInstalled:
                return "The Notes app is not installed on this Mac."
            case .permissionDenied:
                return "HotDock is not allowed to control Notes. Grant it in System Settings › Privacy & Security › Automation, then try again."
            case .scriptFailed(let detail):
                return "Notes returned an error: \(detail)"
            case .unreadable(let detail):
                return "Could not read that file: \(detail)"
            }
        }
    }

    // MARK: Text files

    /// Shows an open panel and returns the file's text. The app has no Dock icon, so it has to
    /// activate explicitly or the panel can open behind whatever you were using.
    static func chooseTextFile() -> (title: String, text: String)? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose a script"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        var types: [UTType] = [.plainText, .text, .utf8PlainText]
        if let markdown = UTType("net.daringfireball.markdown") { types.append(markdown) }
        panel.allowedContentTypes = types
        panel.allowsOtherFileTypes = true

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        guard let text = readText(at: url) else { return nil }
        return (url.deletingPathExtension().lastPathComponent, text)
    }

    private static func readText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) { return text }
        // Not everything exported from an old app is UTF-8; fall back rather than failing.
        for encoding: String.Encoding in [.utf16, .isoLatin1, .macOSRoman] {
            if let text = try? String(contentsOf: url, encoding: encoding) { return text }
        }
        return nil
    }

    // MARK: Notes

    struct NoteRef: Identifiable, Hashable {
        let id: String
        let name: String
    }

    static var notesInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Notes") != nil
    }

    /// Note names and ids, most recently modified first.
    ///
    /// Three bulk fetches rather than a loop over the notes: asking for a property of *every*
    /// note is one Apple Event, while `repeat with n in notes` sends one per note per property
    /// and takes seconds on a large library.
    static func listNotes(limit: Int = 60) throws -> [NoteRef] {
        guard notesInstalled else { throw ImportError.notesNotInstalled }
        let source = """
        tell application "Notes"
            return {id of every note, name of every note, modification date of every note}
        end tell
        """
        let result = try run(source)
        guard let ids = result.atIndex(1),
              let names = result.atIndex(2),
              let dates = result.atIndex(3) else { return [] }

        var refs: [(ref: NoteRef, date: Date)] = []
        for index in 1...max(1, ids.numberOfItems) where ids.numberOfItems > 0 {
            guard let id = ids.atIndex(index)?.stringValue else { continue }
            let name = names.atIndex(index)?.stringValue ?? ""
            let date = dates.atIndex(index)?.dateValue ?? .distantPast
            refs.append((NoteRef(id: id, name: name), date))
        }
        return refs.sorted { $0.date > $1.date }.prefix(limit).map(\.ref)
    }

    /// The note's text. Notes stores bodies as HTML, so convert rather than showing the markup.
    static func noteText(id: String) throws -> String {
        let escaped = id.replacingOccurrences(of: "\"", with: "\\\"")
        let result = try run("tell application \"Notes\" to return body of note id \"\(escaped)\"")
        let html = result.stringValue ?? ""
        return htmlToPlainText(html)
    }

    private static func htmlToPlainText(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html,
                          .characterEncoding: String.Encoding.utf8.rawValue],
                documentAttributes: nil)
        else { return html }
        return attributed.string
    }

    private static func run(_ source: String) throws -> NSAppleEventDescriptor {
        guard let script = NSAppleScript(source: source) else {
            throw ImportError.scriptFailed("could not compile")
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            // -1743 is "not authorised to send Apple Events"; -600 is "app isn't running".
            if code == -1743 { throw ImportError.permissionDenied }
            let message = error[NSAppleScript.errorMessage] as? String ?? "error \(code)"
            throw ImportError.scriptFailed(message)
        }
        return result
    }
}
