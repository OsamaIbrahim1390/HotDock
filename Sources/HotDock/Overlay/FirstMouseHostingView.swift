import AppKit
import SwiftUI

/// An `NSHostingView` that responds to the very first click.
///
/// The overlay is a non-activating panel that never becomes key, so by default AppKit treats a
/// click on it as "activate me" and swallows it — buttons inside would need a second click.
/// Accepting first mouse means one click does what it looks like it does, while the app you
/// are presenting in keeps focus.
final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {

    /// Scroll wheel / trackpad scrolling over the card. Delta is in points for a trackpad
    /// (`hasPreciseScrollingDeltas`) and in lines for an old-fashioned mouse wheel.
    var onScroll: ((CGFloat, Bool) -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit delivers a scroll to the deepest view under the cursor and then walks up the
    /// responder chain. SwiftUI `Text` does not consume scrolls, so one over the script reaches
    /// us here — while one over the drawer is swallowed by the drawer's own ScrollView first,
    /// which is exactly the behaviour we want.
    override func scrollWheel(with event: NSEvent) {
        guard let onScroll else {
            super.scrollWheel(with: event)
            return
        }
        onScroll(event.scrollingDeltaY, event.hasPreciseScrollingDeltas)
    }

    // Both are `required` on NSHostingView, so a subclass has to restate them. No @MainActor
    // here: adding it would make this isolated where the superclass is not, and callers would
    // need to hop actors for what is already main-thread-only AppKit code.
    required init(rootView: Content) { super.init(rootView: rootView) }
    required init?(coder: NSCoder) { fatalError("not used") }
}
