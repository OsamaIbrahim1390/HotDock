import AppKit
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let settings = Settings.shared
    private var engine: TeleprompterEngine!
    private let notes = NoteStore()
    private let spotify = SpotifyWatcher()
    private var notesList: NotesListWindowController!
    private var observers: Set<AnyCancellable> = []
    private var overlay: OverlayController!
    private var menuBar: MenuBarController!
    private var settingsWindow: SettingsWindowController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppPaths.ensure(AppPaths.support)

        engine = TeleprompterEngine(settings: settings)
        overlay = OverlayController(settings: settings, engine: engine,
                                    notes: notes, spotify: spotify)
        notesList = NotesListWindowController(store: notes)
        menuBar = MenuBarController(overlay: overlay, settings: settings,
                                    engine: engine, notes: notes)
        settingsWindow = SettingsWindowController(settings: settings)
        menuBar.onOpenSettings = { [weak settingsWindow] in settingsWindow?.show() }
        menuBar.onShowNotes = { [weak notesList] in notesList?.show() }
        menuBar.onNewSession = { [weak self] in
            guard let self else { return }
            self.notes.startSession(named: self.engine.documentTitle)
        }

        // Only run the Spotify watcher while the feature is on, so a disabled mini player
        // sends no Apple Events and triggers no permission prompt.
        settings.$spotifyEnabled
            .removeDuplicates()
            .sink { [weak self] enabled in
                guard let self else { return }
                enabled ? self.spotify.start() : self.spotify.stop()
            }
            .store(in: &observers)

        // Starting a script begins a note session, so an interview's notes are grouped under
        // the script you were reading — without you having to remember to start one.
        engine.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self, playing, self.notes.currentSession == nil else { return }
                self.notes.startSession(named: self.engine.documentTitle)
            }
            .store(in: &observers)

        if settings.overlayEnabled {
            overlay.enable()
        }

        Log.write("launched (build \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"))")
    }

    // Accessory app: never show a Dock icon or app switcher entry, even if a window opens.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
