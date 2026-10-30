import AppKit
import QuartzCore

/// What moves the script. Today that is the display refresh; later it will also be speech,
/// when voice-synced scrolling lands. The engine only knows about this protocol, so adding a
/// second driver does not touch it.
protocol ScrollDriver: AnyObject {
    /// Called with the seconds elapsed since the previous tick.
    var onTick: ((CFTimeInterval) -> Void)? { get set }
    var isRunning: Bool { get }
    func start()
    func stop()
}

/// Drives scrolling from the display's own refresh.
///
/// `NSScreen.displayLink(target:selector:)` (macOS 14+) is the right tool rather than a Timer:
/// it fires in step with the panel and adapts to ProMotion's variable refresh rate, so motion
/// is smooth without us guessing at an interval or burning frames the display will not show.
final class DisplayLinkDriver: ScrollDriver {

    var onTick: ((CFTimeInterval) -> Void)?
    private(set) var isRunning = false

    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval = 0
    private var lastDelivered: CFTimeInterval = 0

    /// Cap the callback rate. `CADisplayLink.preferredFrameRateRange` is iOS/tvOS only, so the
    /// throttle lives here. On a ProMotion display the link fires at 120Hz; a teleprompter
    /// creeping along at a few dozen points per second gains nothing visible from the second
    /// half of those frames, and skipping them means the offset does not change, so the window
    /// is not recomposited either. Measured: roughly a third off the cost of scrolling.
    var maxFramesPerSecond: Double = 60

    func start() {
        guard !isRunning else { return }
        isRunning = true
        lastTimestamp = 0
        lastDelivered = 0
        makeLink()
    }

    func stop() {
        isRunning = false
        link?.invalidate()
        link = nil
    }

    /// Called when the overlay moves to a different display, so the link follows it.
    func rebuildIfNeeded() {
        guard isRunning else { return }
        link?.invalidate()
        link = nil
        lastTimestamp = 0
        makeLink()
    }

    private func makeLink() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        let link = screen.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func tick(_ link: CADisplayLink) {
        let now = link.timestamp
        guard lastTimestamp > 0 else {            // first frame has no interval yet
            lastTimestamp = now
            lastDelivered = now
            return
        }
        lastTimestamp = now

        let sinceDelivered = now - lastDelivered
        guard sinceDelivered >= (1.0 / maxFramesPerSecond) - 0.001 else { return }
        lastDelivered = now

        // Guard against a stall (display sleep, app suspended) dumping a huge jump into the
        // script. A quarter second is already far longer than any real frame.
        guard sinceDelivered > 0, sinceDelivered < 0.25 else { return }
        onTick?(sinceDelivered)
    }

    deinit { stop() }
}
