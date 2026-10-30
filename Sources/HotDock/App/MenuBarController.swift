import AppKit

/// The menu bar item.
///
/// Deliberately short. Everything you reach for while reading — play, restart, speed, text
/// size, notes, the player and its transport — lives in the overlay card itself, so repeating
/// it here would just be a second place to maintain and a longer menu to read. What is left is
/// what the card cannot offer: the master switch, a way to recover the overlay if a display
/// change strands it, the notes browser, and Settings.
final class MenuBarController: NSObject {

    private let statusItem: NSStatusItem
    private let overlay: OverlayController
    private let settings: Settings
    private let engine: TeleprompterEngine
    private let notes: NoteStore

    var onShowNotes: (() -> Void)?
    var onNewSession: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    init(overlay: OverlayController, settings: Settings,
         engine: TeleprompterEngine, notes: NoteStore) {
        self.overlay = overlay
        self.settings = settings
        self.engine = engine
        self.notes = notes
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.line.first.and.arrowtriangle.forward",
                                accessibilityDescription: "HotDock")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "HotDock"
        }

        statusItem.menu = buildMenu()
    }

    private enum Tag {
        static let enableOverlay = 1
        static let session = 2
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        menu.addItem(item("Enable Overlay", #selector(toggleOverlay), tag: Tag.enableOverlay))
        // Worth keeping: if a display change ever strands the overlay, this is the way back.
        menu.addItem(item("Reposition Overlay", #selector(repositionOverlay)))
        // Reachable even when the overlay has been shrunk past the point of being usable.
        menu.addItem(item("Reset Overlay Size", #selector(resetOverlaySize)))

        menu.addItem(.separator())
        // Section jumps have no home in the card yet; they get a shortcut in the next step.
        menu.addItem(item("Next Section", #selector(nextSection)))
        menu.addItem(item("Previous Section", #selector(previousSection)))

        menu.addItem(.separator())
        let sessionItem = NSMenuItem(title: "Notes", action: nil, keyEquivalent: "")
        sessionItem.isEnabled = false
        sessionItem.tag = Tag.session
        menu.addItem(sessionItem)
        menu.addItem(item("Browse Notes…", #selector(showNotes), indent: 1))
        menu.addItem(item("Start New Session", #selector(newSession), indent: 1))

        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
        menu.addItem(item("Quit HotDock", #selector(quit), key: "q"))
        return menu
    }

    private func item(_ title: String, _ action: Selector, tag: Int = 0,
                      key: String = "", indent: Int = 0) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.target = self
        menuItem.tag = tag
        menuItem.indentationLevel = indent
        return menuItem
    }

    @objc private func toggleOverlay() { overlay.toggleEnabled() }
    @objc private func repositionOverlay() { overlay.reposition() }
    @objc private func resetOverlaySize() { settings.resetOverlaySize() }
    @objc private func nextSection() { engine.jumpToNextSection() }
    @objc private func previousSection() { engine.jumpToPreviousSection() }
    @objc private func showNotes() { onShowNotes?() }
    @objc private func newSession() { onNewSession?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension MenuBarController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: Tag.enableOverlay)?.state = overlay.isEnabled ? .on : .off
        menu.item(withTag: Tag.session)?.title = notes.currentSession.map {
            "Notes — \($0.title)"
        } ?? "Notes — no session yet"
    }
}
