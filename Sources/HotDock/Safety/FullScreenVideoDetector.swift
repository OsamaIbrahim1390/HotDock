import AppKit
import IOKit.pwr_mgt

/// Tells us when full-screen video is playing on the notch display, so the glow can get out of
/// the way of a film without disappearing the rest of the time.
///
/// "Any app is full-screen" turned out to be the wrong question: on this Mac, VS Code and
/// Chrome normally run full-screen, so hiding on that would hide the glow nearly always and the
/// "HotDock is on" indicator would be useless. The question is "is a *video* playing
/// full-screen", which needs two signals. Both were measured here, not assumed:
///
/// 1. **Is the active Space a full-screen Space?** On a full-screen Space the desktop does not
///    exist, so the Wallpaper and Dock windows are off-screen; on a normal desktop they are on.
///    Window geometry cannot answer this — Chrome on a notched Mac puts full-screen content
///    below the camera at y=33, the same place a maximized window starts — and sentinel windows
///    cannot either, because on macOS 27 all-Spaces windows join full-screen Spaces at every
///    window level.
///
/// 2. **Is the frontmost app playing video?** Video players hold a
///    `PreventUserIdleDisplaySleep` power assertion while playing — it is what stops the screen
///    dimming during a film. `IOPMCopyAssertionsByProcess` lists them per process.
///
/// Both are public APIs that need no permission and read no pixels or window titles.
final class FullScreenVideoDetector {

    private(set) var isActive = false
    var onChange: ((Bool) -> Void)?

    private var pollTimer: Timer?
    /// No public notification exists for user-level assertions, so we poll — but only touch the
    /// power-management API while a full-screen Space is actually active.
    private let pollInterval: TimeInterval = 1.5
    /// Players drop and retake the assertion while seeking or buffering, and pausing for a
    /// moment should not make the glow flash up over the paused frame.
    private let releaseGrace: TimeInterval = 4
    private var lastVideoSeen: Date?
    /// The grace period belongs to the app that was playing. Switching to a different
    /// full-screen app (say, from a film to your editor) brings the glow back immediately.
    private var lastVideoPID: pid_t?

    func start() {
        guard pollTimer == nil else { return }
        let ws = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            ws.addObserver(self, selector: #selector(checkSoon), name: name, object: nil)
        }
        let timer = Timer(timeInterval: pollInterval, target: self,
                          selector: #selector(check), userInfo: nil, repeats: true)
        timer.tolerance = 0.5
        RunLoop.main.add(timer, forMode: .common)
        pollTimer = timer
        Log.write("full-screen video detector started")
        check()
    }

    func stop() {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        pollTimer?.invalidate()
        pollTimer = nil
        lastVideoSeen = nil
        lastVideoPID = nil
        if isActive { isActive = false; onChange?(false) }
    }

    deinit { stop() }

    /// A Space change arrives before the transition animation has finished, so check now and
    /// again once it has settled.
    @objc private func checkSoon() {
        check()
        for delay in [0.4, 1.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.check() }
        }
    }

    @objc private func check() {
        guard let screen = NotchGeometry.preferredScreen() else { return }

        let fullScreenSpace = !Self.desktopIsVisible(on: screen)
        var videoNow = false
        var frontName = "-"
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        if fullScreenSpace, let front = NSWorkspace.shared.frontmostApplication {
            frontName = front.localizedName ?? "pid \(front.processIdentifier)"
            videoNow = Self.pidsPreventingDisplaySleep().contains(front.processIdentifier)
        }

        let now = Date()
        if videoNow { lastVideoSeen = now; lastVideoPID = frontPID }
        let withinGrace = frontPID != nil && frontPID == lastVideoPID
            && (lastVideoSeen.map { now.timeIntervalSince($0) < releaseGrace } ?? false)
        let active = fullScreenSpace && (videoNow || withinGrace)

        Log.writeIfChanged(key: "fsv",
                           "full-screen space: \(fullScreenSpace ? "yes" : "no"); front: \(frontName); video: \(videoNow ? "playing" : "no")")

        guard active != isActive else { return }
        isActive = active
        Log.write(active ? "full-screen video — hiding glow" : "full-screen video ended")
        onChange?(active)
    }

    // MARK: Signals

    /// True when the desktop (wallpaper or Dock) is on screen on this display, i.e. we are on an
    /// ordinary desktop Space rather than a full-screen one.
    static func desktopIsVisible(on screen: NSScreen) -> Bool {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID)
                as? [[String: Any]] else { return true }   // unsure: never hide on a guess
        // CGWindow bounds use a top-left origin anchored on the primary display.
        let primaryMaxY = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let screenCG = CGRect(x: screen.frame.minX, y: primaryMaxY - screen.frame.maxY,
                              width: screen.frame.width, height: screen.frame.height)
        for window in list {
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  owner == "Wallpaper" || owner == "Dock",
                  let b = window[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            // Each display has its own; only the one on the notch screen counts. Other Spaces'
            // copies are reported thousands of points off to the side and fail this too.
            let overlap = CGRect(x: x, y: y, width: w, height: h).intersection(screenCG)
            if !overlap.isNull && overlap.width * overlap.height >= screenCG.width * screenCG.height * 0.5 {
                return true
            }
        }
        return false
    }

    /// Processes currently holding a "keep the display awake" assertion.
    static func pidsPreventingDisplaySleep() -> Set<pid_t> {
        var byProcess: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&byProcess) == kIOReturnSuccess,
              let dict = byProcess?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [] }
        // Literal values of kIOPMAssertionTypeKey, kIOPMAssertPreventUserIdleDisplaySleep and
        // kIOPMAssertionTypeNoDisplaySleep — CFSTR() macros do not import into Swift.
        let displayTypes: Set<String> = ["PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion"]
        var pids = Set<pid_t>()
        for (pid, assertions) in dict
        where assertions.contains(where: { displayTypes.contains($0["AssertType"] as? String ?? "") }) {
            pids.insert(pid.int32Value)
        }
        return pids
    }
}
