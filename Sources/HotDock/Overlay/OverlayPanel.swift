import AppKit

/// Borderless, transparent, non-activating panel used for the notch overlay.
///
/// Two properties matter most: it must never take focus from the app you are presenting in
/// (`.nonactivatingPanel`, `canBecomeKey == false`), and it must never swallow a click
/// (`ignoresMouseEvents == true` by default — see `OverlayController` for how hover is
/// detected without it).
final class OverlayPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        isMovable = false
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        WindowHardening.applyOverlayBehaviour(self)
    }

    /// Normally false — the card must never pull focus from the app you are presenting in.
    /// Flipped on only while the in-card note editor is open, because you cannot type into a
    /// window that cannot become key.
    var acceptsKeyboard = false

    override var canBecomeKey: Bool { acceptsKeyboard }
    override var canBecomeMain: Bool { false }
}
