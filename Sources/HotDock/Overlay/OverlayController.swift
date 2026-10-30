import AppKit
import SwiftUI
import Combine

/// Owns the notch overlay: the card that slides down, and the silver outline around the notch
/// that shows the app is live.
///
/// Revealing is a SwiftUI animation inside a panel that stays ordered front, rather than a
/// window show/hide — that is what makes the motion smooth instead of popping.
///
/// Hover is deliberately *not* done with an NSTrackingArea. While hidden the card is
/// click-through, so it receives no mouse events of its own and we need the cursor position
/// from outside. Mouse-event monitors need no permission on macOS (only keyboard monitoring
/// does), so this costs nothing in privacy prompts.
final class OverlayController: NSObject, ObservableObject {

    /// Card is on screen (slid down). Drives the animation in `OverlayRootView`.
    @Published private(set) var isRevealed = false
    /// Cursor is over the revealed card. Used to keep it on screen; pausing the script is
    /// handled by the text view itself, which knows where the text actually is.
    @Published private(set) var isHovering = false
    @Published private(set) var diagnostic = ""

    /// Set by the teleprompter: while a script is playing the card stays down regardless of
    /// reveal mode, because you cannot read something that hides when you move the mouse.
    var forceRevealed = false { didSet { if forceRevealed != oldValue { evaluateReveal() } } }

    /// The drawer is open. Also pins the card down — it would be useless if it slid away while
    /// you were reaching for the open panel.
    @Published var isDrawerOpen = false { didSet { if isDrawerOpen != oldValue { evaluateReveal() } } }

    /// The in-card note editor has replaced the script. Also pins the card down.
    @Published var isNoteMode = false { didSet { noteModeChanged(from: oldValue) } }
    /// What is being typed. Lives here so saving does not depend on the view sticking around.
    @Published var noteDraft = ""
    /// Set while editing an existing note rather than writing a new one.
    @Published private(set) var editingNoteID: String?

    private let settings: Settings
    let engine: TeleprompterEngine
    private let notes: NoteStore
    private let spotify: SpotifyWatcher
    private let artwork = ArtworkLoader()
    private var panel: OverlayPanel?
    private var glowPanel: NotchGlowPanel?
    private let fullScreen = FullScreenVideoDetector()
    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?
    private var observers: Set<AnyCancellable> = []

    private let repositionDebouncer = Debouncer(delay: 0.25)
    private let revealDebouncer = Debouncer(delay: 0.10)   // delay supplied per call from Settings
    private let hideDebouncer = Debouncer(delay: 0.45)

    /// How far outside the notch the glow stroke sits, and how much slack its panel needs for
    /// the blurred halo to draw without being clipped. The bottom value is much smaller than
    /// the sides: the gap between the notch (bottom edge y=950) and the top of a maximized
    /// window (y=949) is only 1pt, and anything larger paints the outline onto other apps'
    /// window edges.
    private let glowPadSides: CGFloat = 2.5
    private let glowPadBottom: CGFloat = 1.0
    private let glowRoom: CGFloat = 16

    /// The menu bar band around the notch that triggers a reveal.
    private var triggerZone: CGRect = .zero
    /// Last computed card frame, in global screen coordinates.
    private var panelFrame: CGRect = .zero
    /// Whether the cursor currently asks for the card to be down.
    private var cursorWantsReveal = false

    /// While the size control is being dragged, the card's right edge is pinned here instead
    /// of the card staying centred on the notch.
    ///
    /// Centred growth moves the right-hand side outward by half of every change, and the size
    /// control lives on that side — so the thing you are dragging slides out from under the
    /// cursor as you drag it. Holding the right edge still makes the control stay put.
    private var resizeAnchorMaxX: CGFloat?

    func beginResize() {
        resizeAnchorMaxX = panelFrame.maxX
    }

    func endResize() {
        resizeAnchorMaxX = nil
        reposition(animated: true)
    }

    /// Cursor has to be this far inside the card before we call it a hover, and this far
    /// outside before we drop it — stops a cursor skimming the edge from flickering.
    private let hoverSlop: CGFloat = 6

    init(settings: Settings, engine: TeleprompterEngine,
         notes: NoteStore, spotify: SpotifyWatcher) {
        self.settings = settings
        self.engine = engine
        self.notes = notes
        self.spotify = spotify
        super.init()

        // You cannot read a script that hides when you move the mouse, so playing pins the
        // card down regardless of reveal mode.
        engine.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in self?.forceRevealed = playing }
            .store(in: &observers)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(screenConfigurationChanged),
            name: NSWorkspace.didWakeNotification, object: nil)

        // Geometry settings move the panels immediately.
        Publishers.CombineLatest3(settings.$overlayWidth, settings.$overlayHeight, settings.$revealMargin)
            .dropFirst()
            .sink { [weak self] _, _, _ in self?.reposition() }
            .store(in: &observers)

        settings.$revealMode
            .dropFirst()
            .sink { [weak self] _ in
                // Switching to Always should drop it down at once, not on the next mouse move.
                DispatchQueue.main.async { self?.evaluateReveal(immediate: true) }
            }
            .store(in: &observers)

        settings.$showNotchGlow
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGlowVisibility() } }
            .store(in: &observers)

        settings.$fullScreenGlow
            .dropFirst()
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateGlowVisibility() } }
            .store(in: &observers)

        // Full-screen video should not have our glow sitting on top of it.
        fullScreen.onChange = { [weak self] _ in self?.updateGlowVisibility() }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        removeMouseMonitors()
    }

    // MARK: Enabled / disabled

    var isEnabled: Bool { panel?.isVisible ?? false }

    func enable() {
        let panel = ensurePanel()
        _ = ensureGlowPanel()
        reposition()
        // orderFrontRegardless, not makeKeyAndOrderFront: we must not activate the app.
        panel.orderFrontRegardless()
        installMouseMonitors()
        settings.overlayEnabled = true
        fullScreen.start()
        evaluateReveal(immediate: true)
        updateGlowVisibility()
    }

    func disable() {
        isDrawerOpen = false
        panel?.orderOut(nil)
        glowPanel?.orderOut(nil)
        fullScreen.stop()
        removeMouseMonitors()
        setRevealed(false)
        isHovering = false
        settings.overlayEnabled = false
    }

    func toggleEnabled() { isEnabled ? disable() : enable() }

    /// Used by panic hide, which needs to restore exactly what was on screen before.
    func setEnabledWithoutPersisting(_ enabled: Bool) {
        if enabled {
            let panel = ensurePanel()
            _ = ensureGlowPanel()
            reposition()
            panel.orderFrontRegardless()
            installMouseMonitors()
            fullScreen.start()
            evaluateReveal(immediate: true)
            updateGlowVisibility()
        } else {
            panel?.orderOut(nil)
            glowPanel?.orderOut(nil)
            fullScreen.stop()
            removeMouseMonitors()
            setRevealed(false)
            isHovering = false
        }
    }

    // MARK: Note mode

    private let focusHandoff = FocusHandoff()
    /// Whether the script was running when the editor opened, so it can carry on afterwards.
    private var wasPlayingBeforeNote = false

    private func noteModeChanged(from oldValue: Bool) {
        guard isNoteMode != oldValue, let panel else { return }
        if isNoteMode {
            // A plain toggle always starts a new note; `editNote` sets the draft up first.
            if editingNoteID == nil { noteDraft = "" }
            // Writing and reading at once helps nobody, and the script is hidden anyway.
            wasPlayingBeforeNote = engine.isPlaying
            engine.pause()
            isDrawerOpen = false
            panel.acceptsKeyboard = true
            focusHandoff.take(panel) { [weak panel] in
                panel?.contentView?.firstDescendant(ofType: KeyCatchingTextView.self)
            }
        } else {
            panel.acceptsKeyboard = false
            panel.resignKey()
            focusHandoff.give()
            if wasPlayingBeforeNote { engine.play() }
            wasPlayingBeforeNote = false
        }
        evaluateReveal()
    }

    /// Reopens an existing note in the card editor.
    func editNote(_ note: Note) {
        noteDraft = note.text
        editingNoteID = note.id
        isNoteMode = true
    }

    func saveNote() {
        let text = noteDraft
        let editing = editingNoteID
        noteDraft = ""
        editingNoteID = nil
        isNoteMode = false
        if let editing {
            // Saving an emptied note removes it, which is the obvious way to delete one.
            notes.update(noteID: editing, text: text)
            Log.write("note edited (\(text.count) chars)")
        } else if let note = notes.add(text) {
            Log.write("note saved from card (\(note.text.count) chars)")
        }
    }

    func cancelNote() {
        noteDraft = ""
        editingNoteID = nil
        isNoteMode = false
    }

    // MARK: Panels

    private func ensurePanel() -> OverlayPanel {
        if let panel { return panel }
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: settings.overlayWidth,
                                                     height: settings.overlayHeight))
        let host = FirstMouseHostingView(
            rootView: OverlayRootView(settings: settings, overlay: self,
                                      engine: engine, notes: notes,
                                      spotify: spotify, artwork: artwork))
        host.onScroll = { [weak self] delta, precise in
            guard let self else { return }
            self.engine.scrollByWheel(delta, precise: precise,
                                      sensitivity: self.settings.wheelSensitivity)
        }
        panel.contentView = host
        self.panel = panel
        return panel
    }

    private func ensureGlowPanel() -> NotchGlowPanel {
        if let glowPanel { return glowPanel }
        let p = NotchGlowPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 50))
        self.glowPanel = p
        return p
    }

    /// The glow view needs the notch size baked in, so it is rebuilt whenever geometry changes.
    private func refreshGlowContent(notchSize: CGSize) {
        guard let glowPanel else { return }
        let dark = glowShouldBeDark
        lastGlowDark = dark
        glowPanel.contentView = NotchGlowLayerView(notchSize: notchSize,
                                                   pad: glowPadSides,
                                                   padBottom: glowPadBottom,
                                                   dark: dark)
    }

    /// Throw the glow's view away when it is not on screen, so nothing is left animating
    /// behind an ordered-out window.
    private func tearDownGlowContent() {
        guard let glowPanel, glowPanel.contentView is NotchGlowLayerView else { return }
        glowPanel.contentView = NSView(frame: .zero)
        lastGlowDark = nil
    }

    private var lastNotchSize: CGSize = .zero
    private var lastGlowDark: Bool?

    /// The outline is the indicator for "running but tucked away", so it is shown only while
    /// the card is up. Once the card slides down it would just be a stray line above it, and
    /// during full-screen video it should be out of the way entirely.
    private var glowShouldShow: Bool {
        guard settings.showNotchGlow, isEnabled, !isRevealed else { return false }
        if fullScreen.isActive && settings.fullScreenGlow == .hide { return false }
        return true
    }

    private var glowShouldBeDark: Bool {
        fullScreen.isActive && settings.fullScreenGlow == .dark
    }

    private func updateGlowVisibility(animated: Bool = true, rebuildContent: Bool = false) {
        guard let glowPanel else { return }
        if glowShouldShow {
            let needsContent = rebuildContent
                || !(glowPanel.contentView is NotchGlowLayerView)
                || lastGlowDark != glowShouldBeDark
            if needsContent { refreshGlowContent(notchSize: lastNotchSize) }
            if !glowPanel.isVisible {
                glowPanel.alphaValue = 0
                glowPanel.orderFrontRegardless()
            }
            fadeGlow(to: 1, animated: animated)
        } else if glowPanel.isVisible {
            fadeGlow(to: 0, animated: animated)
        } else {
            tearDownGlowContent()
        }
    }

    private func fadeGlow(to alpha: CGFloat, animated: Bool) {
        guard let glowPanel else { return }
        guard animated else {
            glowPanel.alphaValue = alpha
            if alpha == 0 { glowPanel.orderOut(nil) }
            return
        }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.2
            glowPanel.animator().alphaValue = alpha
        }, completionHandler: { [weak self] in
            // Re-check: the cursor may have left again while this fade was running.
            guard let self, let glowPanel = self.glowPanel else { return }
            if !self.glowShouldShow, glowPanel.alphaValue == 0 {
                glowPanel.orderOut(nil)
                self.tearDownGlowContent()
            }
        })
    }

    // MARK: Positioning

    @objc private func screenConfigurationChanged() {
        // Several notifications arrive for one physical change; act once, and only after the
        // window server has settled, otherwise we read stale screen frames.
        repositionDebouncer.call { [weak self] in self?.reposition() }
    }

    func reposition(animated: Bool = false) {
        guard let panel else { return }
        guard let screen = NotchGeometry.preferredScreen() else {
            diagnostic = "no screen available"
            return
        }
        let metrics = NotchGeometry.metrics(for: screen)
        diagnostic = NotchGeometry.describe(metrics)
        Log.write(diagnostic)

        let width = max(120, CGFloat(settings.overlayWidth))
        let height = max(40, CGFloat(settings.overlayHeight))
        let screenFrame = screen.frame

        // Hang the card from the bottom edge of the notch, centred on it, so the text sits as
        // close to the camera as possible. Clamp horizontally so an odd screen report can never
        // push it off-screen.
        var x = resizeAnchorMaxX.map { $0 - width } ?? (metrics.centerX - width / 2)
        x = min(max(x, screenFrame.minX + 4), screenFrame.maxX - width - 4)
        let frame = NSRect(x: x, y: metrics.contentTopY - height, width: width, height: height)
        if animated {
            // Slide back to centred when the drag ends, rather than snapping.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
        panelFrame = frame

        // The reveal zone is the menu bar band directly above the card, only as wide as the
        // notch plus a small margin. macOS never draws menu titles under the notch, so a narrow
        // zone here will not fight with an app's menus.
        let margin = max(0, CGFloat(settings.revealMargin))
        triggerZone = CGRect(x: metrics.notchRect.minX - margin,
                             y: metrics.notchRect.minY,
                             width: metrics.notchRect.width + margin * 2,
                             height: max(metrics.notchRect.height, screenFrame.maxY - metrics.notchRect.minY))

        // Glow panel: notch plus padding, plus slack for the halo. Top edge flush with the top
        // of the screen so the shape's own top edge falls inside the invisible cut-out.
        let notch = metrics.notchRect
        lastNotchSize = notch.size
        let glowFrame = NSRect(x: notch.minX - glowPadSides - glowRoom,
                               y: notch.minY - glowPadBottom - glowRoom,
                               width: notch.width + (glowPadSides + glowRoom) * 2,
                               height: notch.height + glowPadBottom + glowRoom)
        glowPanel?.setFrame(glowFrame, display: true)
        // Rebuild the content: the view bakes in the notch size, which may have just changed.
        updateGlowVisibility(animated: false, rebuildContent: true)

        Log.write(String(format: "HotDock: card %.0fx%.0f at (%.0f,%.0f) | zone %.0fx%.0f at (%.0f,%.0f) | glow %.0fx%.0f at (%.0f,%.0f) | level %d | sharing %d",
                     frame.width, frame.height, frame.minX, frame.minY,
                     triggerZone.width, triggerZone.height, triggerZone.minX, triggerZone.minY,
                     glowFrame.width, glowFrame.height, glowFrame.minX, glowFrame.minY,
                     panel.level.rawValue, panel.sharingType.rawValue))

        // The display link must follow the overlay if it moved to another screen.
        engine.displayChanged()

        updateCursorState(at: NSEvent.mouseLocation)
    }

    // MARK: Cursor tracking and reveal

    private func installMouseMonitors() {
        guard globalMouseMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.updateCursorState(at: NSEvent.mouseLocation)
        }
        // While the card is accepting clicks, its own mouse-moved events come to us instead of
        // to the global monitor, so we need the local one too.
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.updateCursorState(at: NSEvent.mouseLocation)
            return event
        }
    }

    private func removeMouseMonitors() {
        if let m = globalMouseMonitor { NSEvent.removeMonitor(m); globalMouseMonitor = nil }
        if let m = localMouseMonitor { NSEvent.removeMonitor(m); localMouseMonitor = nil }
    }

    private func updateCursorState(at point: NSPoint) {
        guard let panel, panel.isVisible else {
            if isHovering { isHovering = false }
            return
        }

        let inZone = triggerZone.contains(point)
        let slop = isHovering ? -hoverSlop : hoverSlop   // hysteresis
        let inPanel = panelFrame.insetBy(dx: slop, dy: slop).contains(point)

        // While hidden, only the notch zone reveals: the card's own area sits in the middle of
        // the screen top and must not count, or the overlay would appear whenever the cursor
        // passed through empty space. Once revealed, staying anywhere over it keeps it down.
        cursorWantsReveal = isNoteMode || isDrawerOpen
            || (isRevealed ? (inZone || inPanel) : inZone)

        let hovering = isRevealed && inPanel
        if hovering != isHovering { isHovering = hovering }

        evaluateReveal()
    }

    /// Decides whether the card should be down, honouring reveal mode, the teleprompter
    /// override, and the dwell/grace delays.
    private func evaluateReveal(immediate: Bool = false) {
        guard let panel, panel.isVisible else { return }

        if settings.revealMode == .always || forceRevealed || isDrawerOpen || isNoteMode {
            revealDebouncer.cancel(); hideDebouncer.cancel()
            setRevealed(true)
            return
        }

        if cursorWantsReveal {
            hideDebouncer.cancel()
            guard !isRevealed else { return }
            if immediate { setRevealed(true); return }
            revealDebouncer.call(after: settings.revealDelay) { [weak self] in
                guard let self, self.cursorWantsReveal else { return }
                self.setRevealed(true)
            }
        } else {
            revealDebouncer.cancel()
            guard isRevealed else { return }
            if immediate { setRevealed(false); return }
            hideDebouncer.call(after: settings.hideDelay) { [weak self] in
                guard let self, !self.cursorWantsReveal else { return }
                self.setRevealed(false)
            }
        }
    }

    private func setRevealed(_ revealed: Bool) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        if !revealed { isHovering = false }

        // Clicks land on the card while it is down, and pass straight through while it is not.
        // A nonactivating panel that cannot become key means capturing a click still does not
        // take focus away from the app you are presenting in.
        panel?.ignoresMouseEvents = !revealed
        panel?.acceptsMouseMovedEvents = revealed

        updateGlowVisibility()
    }
}
