import AppKit

/// Borrows keyboard focus and gives it straight back.
///
/// HotDock's panels are non-activating, which is the whole point — they must not pull focus
/// from whatever you are presenting in. But you cannot type into a window that never becomes
/// key. A non-activating panel is *supposed* to take the keyboard without activating its app;
/// for an accessory app that is unreliable, so this tries it first and only activates if the
/// panel did not get the keyboard. Either way the previous app is reactivated the moment focus
/// is handed back, so it is away for as long as the typing takes and no longer.
final class FocusHandoff {

    private var previousApp: NSRunningApplication?
    private var didActivate = false

    /// - Parameter firstResponder: the view to put the caret in, resolved after focus settles.
    func take(_ window: NSWindow, firstResponder: @escaping () -> NSView?) {
        previousApp = NSWorkspace.shared.frontmostApplication
        didActivate = false
        window.makeKeyAndOrderFront(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self, weak window] in
            guard let self, let window, window.isVisible else { return }
            if !window.isKeyWindow {
                self.didActivate = true
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
            if let responder = firstResponder() {
                window.makeFirstResponder(responder)
            }
        }
    }

    func give() {
        defer {
            previousApp = nil
            didActivate = false
        }
        guard didActivate,
              let previousApp,
              previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        previousApp.activate()
    }
}

extension NSView {
    /// First descendant of the given type — used to hand first responder to a text view.
    func firstDescendant<T: NSView>(ofType type: T.Type) -> T? {
        if let match = self as? T { return match }
        for subview in subviews {
            if let found = subview.firstDescendant(ofType: type) { return found }
        }
        return nil
    }
}
