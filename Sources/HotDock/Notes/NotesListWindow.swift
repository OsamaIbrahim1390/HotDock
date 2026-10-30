import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct NotesListView: View {
    @ObservedObject var store: NoteStore
    @State private var selection: String?
    @State private var query = ""

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private var selectedSession: NoteSession? {
        store.sessions.first { $0.id == selection } ?? store.sessions.first
    }

    /// Searching filters the notes inside the chosen session; an empty query shows everything.
    private var visibleNotes: [Note] {
        guard let session = selectedSession else { return [] }
        guard !query.isEmpty else { return session.notes }
        return session.notes.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationSplitView {
            List(store.sessions, selection: $selection) { session in
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.title).lineLimit(1)
                    Text("\(session.notes.count) note\(session.notes.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .tag(session.id)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let session = selectedSession {
                detail(session)
            } else {
                ContentUnavailableView("No notes yet",
                                       systemImage: "note.text",
                                       description: Text("Notes you take during a session appear here."))
            }
        }
        .searchable(text: $query, prompt: "Search notes in this session")
        .frame(minWidth: 680, minHeight: 420)
        .onAppear { store.reload() }
    }

    private func detail(_ session: NoteSession) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(session.title).font(.headline)
                Spacer()
                Button("Copy as Markdown") { copyMarkdown(session) }
                Button("Export…") { export(session) }
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([session.fileURL])
                }
            }
            .padding(12)

            Divider()

            if visibleNotes.isEmpty {
                ContentUnavailableView(query.isEmpty ? "No notes in this session" : "No matches",
                                       systemImage: query.isEmpty ? "note.text" : "magnifyingglass")
            } else {
                List(visibleNotes) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(Self.timeFormatter.string(from: note.date))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(note.text).textSelection(.enabled)
                    }
                    .padding(.vertical, 3)
                    .contextMenu {
                        Button("Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(note.text, forType: .string)
                        }
                    }
                }
            }
        }
    }

    private func copyMarkdown(_ session: NoteSession) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(store.markdown(for: session), forType: .string)
    }

    private func export(_ session: NoteSession) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = session.fileURL.lastPathComponent
        if let markdown = UTType("net.daringfireball.markdown") {
            panel.allowedContentTypes = [markdown, .plainText]
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? store.markdown(for: session).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Owns the notes browser window. One window, reused.
final class NotesListWindowController: NSObject {

    private let store: NoteStore
    private var window: NSWindow?

    init(store: NoteStore) {
        self.store = store
        super.init()
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: NotesListView(store: store))
            let window = NSWindow(contentViewController: hosting)
            window.title = "HotDock Notes"
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("HotDockNotes")
            WindowHardening.applyStandardBehaviour(window)
            self.window = window
        }
        store.reload()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
