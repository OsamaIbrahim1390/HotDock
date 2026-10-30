import AppKit

/// Every window and panel in the app goes through here, so no window can be forgotten
/// when we change the privacy or layering rules.
enum WindowHardening {

    /// Level for the notch overlay and other always-on-top panels.
    ///
    /// `CGWindowLevelForKey(.statusWindow)` (25) is the level the menu bar extras live at;
    /// one above that puts us over the menu bar. Combined with `.fullScreenAuxiliary` and
    /// `.canJoinAllApplications` this also floats over other apps' full-screen spaces.
    static let overlayLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

    /// Ask the window server not to let other processes read this window's pixels.
    ///
    /// Be clear about what this does and does not buy you: `.none` is honoured by the older
    /// `CGWindowListCreateImage` capture path, but since macOS 15.4 ScreenCaptureKit-based
    /// capture — which is what current Zoom, Teams, Chrome (Google Meet) and QuickTime use —
    /// captures `.none` windows anyway (Apple Developer Forums thread 792152, WebRTC issue
    /// 41480865). We set it because it costs nothing and helps where it is honoured, but the
    /// protection you should actually rely on is sharing a single window instead of the whole
    /// screen. "Test visibility" in the menu bar lets you check this on your own macOS.
    static func hideFromScreenCapture(_ window: NSWindow) {
        window.sharingType = .none
    }

    /// Floating, all-Spaces, over-full-screen behaviour for overlay-style panels.
    static func applyOverlayBehaviour(_ window: NSWindow) {
        hideFromScreenCapture(window)
        window.level = overlayLevel
        window.collectionBehavior = [
            .canJoinAllSpaces,         // visible on every Space
            .stationary,               // does not slide during Space transitions
            .fullScreenAuxiliary,      // allowed alongside another app's full-screen window
            .canJoinAllApplications,   // may join other apps' window sets (macOS 13+)
            .ignoresCycle,             // never shows up in Cmd-` cycling
        ]
        window.hidesOnDeactivate = false
        window.isExcludedFromWindowsMenu = true
    }

    /// Ordinary app windows (editor, settings, notes list): screen-capture hidden, but
    /// otherwise normal windows the user can move, focus and close.
    static func applyStandardBehaviour(_ window: NSWindow) {
        hideFromScreenCapture(window)
    }
}
