import SwiftUI
import Combine

/// The scrolling state machine: what is loaded, where we are in it, and whether it is moving.
///
/// Geometry (`contentHeight`, `viewportHeight`, section positions) is measured by the view and
/// pushed back in, so the engine never has to guess how text will wrap.
final class TeleprompterEngine: ObservableObject {

    @Published private(set) var document: ScriptDocument
    /// Shown in the drawer so you can tell which script is loaded.
    @Published private(set) var documentTitle: String
    /// What the user asked for. Separate from `isScrolling`, which also accounts for hover.
    @Published private(set) var isPlaying = false
    /// Points scrolled down from the top of the script.
    @Published var offset: CGFloat = 0
    /// Cursor is resting over the overlay, so hold position until it leaves.
    @Published var isPausedByHover = false

    @Published private(set) var contentHeight: CGFloat = 0
    @Published private(set) var viewportHeight: CGFloat = 0

    /// Where each heading sits inside the content, keyed by block id. Measured by the view.
    private(set) var sectionOffsets: [Int: CGFloat] = [:]

    private let settings: Settings
    private let driver: ScrollDriver

    init(settings: Settings, driver: ScrollDriver = DisplayLinkDriver()) {
        self.settings = settings
        self.driver = driver
        self.document = ScriptDocument.sample
        self.documentTitle = "Sample script"
        driver.onTick = { [weak self] delta in self?.tick(delta) }
    }

    // MARK: Transport

    /// Actually moving right now: playing, not held by hover, and not already at the end.
    var isScrolling: Bool { isPlaying && !isPausedByHover && offset < maxOffset }

    var maxOffset: CGFloat { max(0, contentHeight - viewportHeight) }
    var isAtEnd: Bool { offset >= maxOffset - 0.5 }

    func play() {
        guard !isPlaying else { return }
        // Starting again from the very end would do nothing visible, so wrap to the top.
        if isAtEnd { offset = 0 }
        isPlaying = true
        driver.start()
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        driver.stop()
    }

    func togglePlay() { isPlaying ? pause() : play() }

    func restart() {
        offset = 0
    }

    /// Called when the overlay moves to another display.
    func displayChanged() {
        (driver as? DisplayLinkDriver)?.rebuildIfNeeded()
    }

    // MARK: Speed

    func changeSpeed(by delta: Double) {
        settings.scrollSpeed = min(400, max(5, settings.scrollSpeed + delta))
    }

    // MARK: Manual movement

    /// Positive moves forward through the script, negative back.
    func nudge(by points: CGFloat) {
        offset = min(maxOffset, max(0, offset + points))
    }

    /// Trackpad or mouse-wheel scrolling over the script.
    ///
    /// `scrollingDeltaY` already has the system's "natural scrolling" preference applied, so
    /// subtracting it gives the same direction of travel as every other document on the Mac.
    /// A trackpad reports precise deltas in points, which are used as-is so the script moves
    /// exactly with your fingers; a mouse wheel reports lines, converted at a typical line
    /// height.
    func scrollByWheel(_ deltaY: CGFloat, precise: Bool, sensitivity: Double) {
        let points = precise ? deltaY : deltaY * 16
        nudge(by: -points * CGFloat(sensitivity))
    }

    /// Jump to a fraction of the way through the script, from the scrollbar.
    func scrub(toProgress progress: CGFloat) {
        guard maxOffset > 0 else { return }
        offset = min(maxOffset, max(0, maxOffset * min(1, max(0, progress))))
    }

    func jumpToNextSection() { jump(forward: true) }
    func jumpToPreviousSection() { jump(forward: false) }

    private func jump(forward: Bool) {
        let positions = document.sections
            .compactMap { sectionOffsets[$0.id] }
            .sorted()
        guard !positions.isEmpty else { return }
        // A small tolerance stops "next" landing on the heading we are already sitting on.
        let tolerance: CGFloat = 2
        let target: CGFloat?
        if forward {
            target = positions.first { $0 > offset + tolerance }
        } else {
            target = positions.last { $0 < offset - tolerance }
        }
        offset = min(maxOffset, max(0, target ?? (forward ? maxOffset : 0)))
    }

    // MARK: Content

    func load(_ document: ScriptDocument, title: String) {
        pause()
        self.document = document
        self.documentTitle = title
        sectionOffsets = [:]
        contentHeight = 0        // re-measured by the view for the new text
        offset = 0
    }

    func updateSectionOffsets(_ offsets: [Int: CGFloat]) {
        sectionOffsets = offsets
    }

    /// Geometry comes from SwiftUI measurements, which re-run on every layout pass. `@Published`
    /// fires on every assignment — even an identical one — so writing straight through would
    /// re-render the view that produced the measurement and spin the layout engine forever.
    /// Sub-pixel noise is not worth a redraw either, hence the tolerance.
    func setContentHeight(_ height: CGFloat) {
        guard abs(contentHeight - height) > 0.5 else { return }
        contentHeight = height
    }

    func setViewportHeight(_ height: CGFloat) {
        guard abs(viewportHeight - height) > 0.5 else { return }
        viewportHeight = height
    }

    // MARK: Driver

    private func tick(_ delta: CFTimeInterval) {
        guard isPlaying, !isPausedByHover else { return }
        let next = offset + CGFloat(settings.scrollSpeed) * CGFloat(delta)
        if next >= maxOffset {
            offset = maxOffset
            pause()      // reached the end; stop cleanly rather than spinning at the bottom
        } else {
            offset = next
        }
    }
}
