import AppKit

struct NotchMetrics {
    let screen: NSScreen
    let hasNotch: Bool
    /// The notch itself on a notched display, or a synthetic top-centre strip otherwise.
    /// Global screen coordinates, bottom-left origin (AppKit convention).
    let notchRect: CGRect
    /// Height of the menu bar band the notch sits in.
    let topInset: CGFloat

    /// Where overlay content should hang from: the bottom edge of the notch.
    var contentTopY: CGFloat { notchRect.minY }
    var centerX: CGFloat { notchRect.midX }
}

enum NotchGeometry {

    /// Swift imports `auxiliaryTop*Area` as optional: nil means the display has no unobscured
    /// area beside a notch, i.e. no notch at all.
    private static func sideAreas(_ screen: NSScreen) -> (left: CGFloat, right: CGFloat) {
        (screen.auxiliaryTopLeftArea?.width ?? 0, screen.auxiliaryTopRightArea?.width ?? 0)
    }

    /// Prefer a display that actually has a notch; otherwise the display with the menu bar.
    /// Re-resolved on every screen change so closing the lid or unplugging a monitor moves
    /// the overlay instead of leaving it off-screen.
    static func preferredScreen() -> NSScreen? {
        if let notched = NSScreen.screens.first(where: { isNotched($0) }) { return notched }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func isNotched(_ screen: NSScreen) -> Bool {
        guard screen.safeAreaInsets.top > 0 else { return false }
        let (left, right) = sideAreas(screen)
        // A notched display reports two unobscured side areas that together are narrower than
        // the screen; the gap between them is the notch.
        let sides = left + right
        return sides > 0 && sides < screen.frame.width
    }

    static func metrics(for screen: NSScreen) -> NotchMetrics {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        guard isNotched(screen) else {
            // No notch: pretend there is a small strip at top centre, under the menu bar, so
            // the overlay still lands somewhere sensible on an external display.
            let menuBar = max(topInset, NSStatusBar.system.thickness)
            let synthetic = CGRect(x: frame.midX - 100,
                                   y: frame.maxY - menuBar,
                                   width: 200,
                                   height: menuBar)
            return NotchMetrics(screen: screen, hasNotch: false, notchRect: synthetic, topInset: menuBar)
        }

        let (left, right) = sideAreas(screen)
        // The notch is the gap between the two unobscured areas. Derive it from their widths
        // rather than assuming it is centred, so an asymmetric report still lines up.
        let rect = CGRect(x: frame.minX + left,
                          y: frame.maxY - topInset,
                          width: max(0, frame.width - left - right),
                          height: topInset)
        return NotchMetrics(screen: screen, hasNotch: true, notchRect: rect, topInset: topInset)
    }

    /// One-line description used by the diagnostic log on launch and after screen changes.
    static func describe(_ m: NotchMetrics) -> String {
        let f = m.screen.frame
        let (left, right) = sideAreas(m.screen)
        return String(format: "screen \"%@\" %.0fx%.0f at (%.0f,%.0f) | notch:%@ %.0fx%.0f at (%.0f,%.0f) | topInset %.1f | auxL %.0f auxR %.0f",
                      m.screen.localizedName, f.width, f.height, f.minX, f.minY,
                      m.hasNotch ? "yes" : "no",
                      m.notchRect.width, m.notchRect.height, m.notchRect.minX, m.notchRect.minY,
                      m.topInset, left, right)
    }
}
