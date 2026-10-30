import Foundation
import Combine

struct Note: Identifiable, Equatable {
    /// "<session file stem>#<timestamp>#<hash of the text>".
    ///
    /// Not a UUID: notes are re-read from disk on every reload, so a fresh UUID each time
    /// would mean nothing could refer to a note for longer than a moment — unpinning it, or
    /// opening it to edit, would both break.
    ///
    /// Not a position either. Any id derived from a note's place in the list is renumbered
    /// when an earlier note is deleted, so an id held elsewhere silently starts pointing at a
    /// different note — measured: deleting the first of three notes re-pinned one that had
    /// been unpinned. Deriving it from the content instead makes it independent of order.
    /// Editing a note changes its id, which simply re-pins it; that is the right outcome for
    /// a note you just rewrote.
    let id: String
    let date: Date
    var text: String
}

struct NoteSession: Identifiable, Equatable {
    /// Filename stem, which is also a stable id.
    let id: String
    let title: String
    let started: Date
    var notes: [Note]
    var fileURL: URL
}

/// Notes on disk, grouped into sessions.
///
/// One Markdown file per session in Application Support — readable in any editor, and the
/// export is simply a copy of the file rather than a conversion. Nothing is synced anywhere.
final class NoteStore: ObservableObject {

    @Published private(set) var currentSession: NoteSession?
    /// Most recent first. Rebuilt from disk, so editing a file by hand is picked up.
    @Published private(set) var sessions: [NoteSession] = []
    /// Set when mirroring to the Notes app fails, so the UI can say so instead of going quiet.
    @Published private(set) var syncProblem: String?

    private let folder = AppPaths.notes

    /// Timestamps inside a file use a fixed format rather than the user's locale, so a file
    /// written on a machine set to one region still parses on another.
    private static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static let fileStemFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HHmm"
        return f
    }()

    /// Fixed locale here too. With the user's locale, a 12-hour region silently rewrites
    /// "HH:mm" as "6:30 PM", which reads badly in a filename-adjacent title and sorts worse.
    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "d MMM yyyy, HH:mm"
        return f
    }()

    init() {
        AppPaths.ensure(folder)
        reload()
    }

    // MARK: Sessions

    /// Starts a new session. Called when a script starts, or from the menu bar.
    @discardableResult
    func startSession(named name: String) -> NoteSession {
        let started = Date()
        let cleanName = sanitize(name.isEmpty ? "Session" : name)
        let stem = "\(Self.fileStemFormatter.string(from: started)) \(cleanName)"
        let title = "\(cleanName) – \(Self.titleFormatter.string(from: started))"
        let url = folder.appendingPathComponent("\(stem).md")

        let session = NoteSession(id: stem, title: title, started: started, notes: [], fileURL: url)
        currentSession = session
        write(session)
        reload()
        Log.write("note session started: \(title)")
        return session
    }

    /// The session new notes go into, creating one if nothing is open yet.
    @discardableResult
    private func ensureSession() -> NoteSession {
        if let currentSession { return currentSession }
        return startSession(named: "Session")
    }

    func resume(_ session: NoteSession) {
        currentSession = session
    }

    // MARK: Notes

    @discardableResult
    func add(_ text: String) -> Note? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var session = ensureSession()
        let now = Date()
        let note = Note(id: Self.noteID(sessionID: session.id, date: now, text: trimmed),
                        date: now, text: trimmed)
        session.notes.append(note)
        currentSession = session
        write(session)          // local file first: it is the source of truth
        reload()
        mirrorToNotesApp(note, session: session)
        return note
    }

    /// Best-effort copy into the Notes app. Runs off the main thread because it is an Apple
    /// Event round trip to another process, and a failure never affects the saved note.
    private func mirrorToNotesApp(_ note: Note, session: NoteSession) {
        guard Settings.shared.syncToNotesApp else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let problem = NotesAppSync.append(text: note.text, at: note.date,
                                              sessionID: session.id, sessionTitle: session.title)
            DispatchQueue.main.async { self?.syncProblem = problem }
        }
    }

    private static func noteID(sessionID: String, date: Date, text: String) -> String {
        "\(sessionID)#\(stampFormatter.string(from: date))#\(stableHash(text))"
    }

    /// FNV-1a. Swift's own `hashValue` is seeded differently on every launch, so it cannot be
    /// used for anything written to disk or remembered in UserDefaults.
    private static func stableHash(_ value: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return String(hash, radix: 36)
    }

    /// Recent notes still pinned to the overlay, newest first.
    var pinnedNotes: [Note] {
        guard let currentSession else { return [] }
        return currentSession.notes.reversed().filter { !dismissed.contains($0.id) }
    }

    /// Changes a note's text in place and rewrites the session file.
    func update(noteID: String, text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard var session = currentSession,
              let index = session.notes.firstIndex(where: { $0.id == noteID }) else { return }
        if trimmed.isEmpty {
            session.notes.remove(at: index)
        } else {
            session.notes[index].text = trimmed
        }
        currentSession = session
        write(session)
        reload()
        // The Notes app copy is append-only, so an edit has to replace the whole body or the
        // two would silently disagree.
        rewriteNotesApp(session: session)
    }

    func note(id: String) -> Note? {
        currentSession?.notes.first { $0.id == id }
    }

    // MARK: Pinning

    /// Ids the user has unpinned. Kept in UserDefaults so they stay unpinned across launches,
    /// and capped so the list cannot grow forever.
    private var dismissed: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: "dismissedNotes") ?? []) }
        set {
            UserDefaults.standard.set(Array(newValue.suffix(300)), forKey: "dismissedNotes")
        }
    }

    func unpin(noteID: String) {
        dismissed.insert(noteID)
        objectWillChange.send()
    }

    // MARK: Disk

    private func write(_ session: NoteSession) {
        var text = "# \(session.title)\n\n"
        for note in session.notes {
            text += "## \(Self.stampFormatter.string(from: note.date))\n\(note.text)\n\n"
        }
        do {
            AppPaths.ensure(folder)
            try text.write(to: session.fileURL, atomically: true, encoding: .utf8)
        } catch {
            Log.write("could not write \(session.fileURL.lastPathComponent): \(error.localizedDescription)")
        }
    }

    func reload() {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: nil)) ?? []
        var loaded: [NoteSession] = []
        for url in urls where url.pathExtension == "md" {
            if let session = parse(url) { loaded.append(session) }
        }
        sessions = loaded.sorted { $0.started > $1.started }
        // Keep the open session's in-memory copy in step with what is on disk.
        if let current = currentSession,
           let refreshed = sessions.first(where: { $0.id == current.id }) {
            currentSession = refreshed
        }
    }

    private func parse(_ url: URL) -> NoteSession? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let stem = url.deletingPathExtension().lastPathComponent
        var title = stem
        var notes: [Note] = []
        var pendingDate: Date?
        var body: [String] = []

        func flush() {
            guard let date = pendingDate else { return }
            let joined = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !joined.isEmpty {
                notes.append(Note(id: Self.noteID(sessionID: stem, date: date, text: joined),
                                  date: date, text: joined))
            }
            body = []
        }

        for line in text.components(separatedBy: "\n") {
            if line.hasPrefix("## ") {
                flush()
                pendingDate = Self.stampFormatter.date(from: String(line.dropFirst(3)))
            } else if line.hasPrefix("# ") {
                title = String(line.dropFirst(2))
            } else {
                body.append(line)
            }
        }
        flush()

        let started = Self.fileStemFormatter.date(from: String(stem.prefix(15)))
            ?? (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate).flatMap { $0 }
            ?? Date.distantPast
        return NoteSession(id: stem, title: title, started: started, notes: notes, fileURL: url)
    }

    /// Keeps a session name usable as a filename without mangling ordinary text.
    private func sanitize(_ name: String) -> String {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name.components(separatedBy: bad).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Export

    private func rewriteNotesApp(session: NoteSession) {
        guard Settings.shared.syncToNotesApp else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let problem = NotesAppSync.replaceBody(sessionID: session.id,
                                                   sessionTitle: session.title,
                                                   notes: session.notes)
            DispatchQueue.main.async { self?.syncProblem = problem }
        }
    }

    /// Markdown for a whole session, for copying or saving elsewhere.
    func markdown(for session: NoteSession) -> String {
        (try? String(contentsOf: session.fileURL, encoding: .utf8)) ?? session.title
    }
}
