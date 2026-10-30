import AppKit

/// A second, very small panel that traces the outline of the notch.
///
/// It exists because the notch band itself is physically not display area — pixels drawn
/// inside the cut-out are invisible — but the pixels immediately left, right and below it are
/// real. Stroking a shape slightly larger than the notch therefore lights up its silhouette.
///
/// Unlike the overlay card, this panel is **always** click-through: it sits over the menu bar
/// either side of the notch, and must never swallow a menu click.
final class NotchGlowPanel: NSPanel {

    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        isMovable = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        WindowHardening.applyOverlayBehaviour(self)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
