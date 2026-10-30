import AppKit
import SwiftUI

/// Owns the Settings window. One window, reused: reopening brings the existing one forward
/// rather than stacking copies.
final class SettingsWindowController: NSObject, NSWindowDelegate {

    private let settings: Settings
    private var window: NSWindow?

    init(settings: Settings) {
        self.settings = settings
        super.init()
    }

    func show() {
        if window == nil { window = makeWindow() }
        guard let window else { return }
        // An accessory app has no Dock icon, so without activating explicitly the window can
        // open behind whatever you were using.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.center()
    }

    private func makeWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(settings: settings))
        let window = NSWindow(contentViewController: hosting)
        window.title = "HotDock Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("HotDockSettings")
        window.delegate = self
        // Same screen-capture handling as every other window in the app.
        WindowHardening.applyStandardBehaviour(window)
        return window
    }
}
