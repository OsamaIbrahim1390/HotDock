import Foundation

/// Mirrors notes into the Notes app, one note per session inside a "HotDock" folder.
///
/// This is a *mirror*, not the storage. The Markdown file in Application Support is still
/// written first and is the source of truth: it needs no permission, works offline, and
/// cannot fail halfway. If Notes is unavailable or you deny automation, you lose the copy in
/// Notes, never the note itself.
///
/// Appending uses the note's id rather than its name, so renaming the note in Notes does not
/// start a second one.
enum NotesAppSync {

    /// Where session note ids are remembered, keyed by session id.
    private static func defaultsKey(_ sessionID: String) -> String { "notesAppID.\(sessionID)" }

    static var isAvailable: Bool {
        ScriptImporter.notesInstalled
    }

    /// Appends one note to the session's note in Notes, creating it on first use.
    /// Returns an error description, or nil on success.
    @discardableResult
    static func append(text: String, at date: Date, sessionID: String,
                       sessionTitle: String) -> String? {
        guard isAvailable else { return "Notes app not installed" }

        let stamp = timeFormatter.string(from: date)
        let fragment = "<div><b>\(escape(stamp))</b></div><div>\(escape(text))</div><div><br></div>"
        let existingID = UserDefaults.standard.string(forKey: defaultsKey(sessionID))

        if let existingID, noteExists(existingID) {
            if let newID = run(appendScript(noteID: existingID, body: fragment)) {
                return newID.isEmpty ? "Notes returned nothing" : nil
            }
            return lastError ?? "Could not append to the note"
        }

        let header = "<div><h1>\(escape(sessionTitle))</h1></div>"
        guard let newID = run(createScript(title: sessionTitle, body: header + fragment)) else {
            return lastError ?? "Could not create the note"
        }
        UserDefaults.standard.set(newID, forKey: defaultsKey(sessionID))
        return nil
    }

    /// Replaces the whole note body. Used after an edit, where appending would leave the old
    /// wording sitting above the new one.
    @discardableResult
    static func replaceBody(sessionID: String, sessionTitle: String,
                            notes: [Note]) -> String? {
        guard isAvailable else { return "Notes app not installed" }
        var html = "<div><h1>\(escape(sessionTitle))</h1></div>"
        for note in notes {
            html += "<div><b>\(escape(timeFormatter.string(from: note.date)))</b></div>"
            html += "<div>\(escape(note.text))</div><div><br></div>"
        }
        guard let id = UserDefaults.standard.string(forKey: defaultsKey(sessionID)),
              noteExists(id) else {
            guard let newID = run(createScript(title: sessionTitle, body: html)) else {
                return lastError ?? "Could not create the note"
            }
            UserDefaults.standard.set(newID, forKey: defaultsKey(sessionID))
            return nil
        }
        let script = """
        tell application "Notes"
            set body of note id "\(quote(id))" to "\(quote(html))"
            return (id of note id "\(quote(id))") as text
        end tell
        """
        return run(script) == nil ? (lastError ?? "Could not update the note") : nil
    }

    // MARK: Scripts

    private static func createScript(title: String, body: String) -> String {
        """
        tell application "Notes"
            if not (exists folder "HotDock") then make new folder with properties {name:"HotDock"}
            set theNote to make new note at folder "HotDock" with properties {name:"\(quote(title))", body:"\(quote(body))"}
            return (id of theNote) as text
        end tell
        """
    }

    private static func appendScript(noteID: String, body: String) -> String {
        """
        tell application "Notes"
            set theNote to note id "\(quote(noteID))"
            set body of theNote to ((body of theNote) & "\(quote(body))")
            return (id of theNote) as text
        end tell
        """
    }

    private static func noteExists(_ id: String) -> Bool {
        run("tell application \"Notes\" to return (exists note id \"\(quote(id))\") as text") == "true"
    }

    // MARK: Plumbing

    private(set) static var lastError: String?

    private static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else {
            lastError = "Could not compile the script"
            return nil
        }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            lastError = code == -1743
                ? "Not allowed to control Notes — System Settings › Privacy & Security › Automation"
                : (error[NSAppleScript.errorMessage] as? String ?? "Notes error \(code)")
            Log.writeIfChanged(key: "notes-sync-error", "notes sync failed: \(lastError ?? "")")
            return nil
        }
        lastError = nil
        return result.stringValue ?? ""
    }

    /// Escapes for embedding inside an AppleScript string literal.
    private static func quote(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
             .replacingOccurrences(of: "\n", with: " ")
    }

    /// Notes bodies are HTML, so the note's own text has to be escaped or a stray `<` eats the
    /// rest of it. Newlines become `<br>` to survive the round trip.
    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
             .replacingOccurrences(of: "<", with: "&lt;")
             .replacingOccurrences(of: ">", with: "&gt;")
             .replacingOccurrences(of: "\n", with: "<br>")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss"
        return f
    }()
}
