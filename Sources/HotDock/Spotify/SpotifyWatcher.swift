import AppKit
import Combine

/// Keeps a live view of what Spotify is playing.
///
/// Spotify broadcasts `com.spotify.client.PlaybackStateChanged` on the distributed
/// notification centre whenever the track or play state changes, and the notification carries
/// most of what we need in its payload. That is the event we listen for — no polling loop
/// hammering Apple Events at an app that is busy decoding audio.
///
/// An Apple Event is still needed for the two things the notification does not carry (artwork
/// URL and volume), plus a slow safety refresh while something is actually playing, in case a
/// notification is missed.
final class SpotifyWatcher: ObservableObject {

    @Published private(set) var state: SpotifyController.PlayerState = .stopped
    @Published private(set) var track: SpotifyController.Track?
    /// -1 until Spotify has actually told us. A made-up starting value is what made the
    /// slider jump: with playback paused the watcher does not poll, so letting go of the
    /// thumb fell back to a default that had never been real.
    @Published private(set) var volume: Int = -1
    var hasVolume: Bool { volume >= 0 }
    @Published private(set) var availability: SpotifyController.Availability = .notRunning

    private var refreshTimer: Timer?
    private var running = false
    private let notificationName = Notification.Name("com.spotify.client.PlaybackStateChanged")

    var isPlaying: Bool { state == .playing }

    /// Whether the player column should exist at all. With Spotify closed or missing there is
    /// nothing to show and no point taking up a column for it.
    var showsPanel: Bool {
        switch availability {
        case .ready, .permissionDenied: return true
        case .notRunning, .notInstalled, .failed: return false
        }
    }

    /// Sets the volume and keeps our value, rather than waiting to be told what it is.
    ///
    /// Spotify stores volume as a float, so a write of 51 reads back as 50 — measured across
    /// the whole range. Correcting the slider for that would drag the thumb backwards under
    /// your finger, so we only accept Spotify's number when it differs by more than its own
    /// rounding error.
    func setVolume(_ value: Int) {
        let clamped = min(100, max(0, value))
        guard clamped != volume else { return }
        volume = clamped
        DispatchQueue.global(qos: .userInitiated).async {
            SpotifyController.setVolume(clamped)
            guard let actual = SpotifyController.currentVolume() else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, abs(actual - clamped) > 1 else { return }
                self.volume = actual
            }
        }
    }

    /// Flip play/pause and update the disc straight away, then let the refresh confirm.
    ///
    /// Waiting for the Apple Event round trip leaves the record sitting still for a moment
    /// after you click it, which reads as the click not having worked.
    func togglePlayPause() {
        SpotifyController.playPause()
        state = (state == .playing) ? .paused : .playing
        refresh()
        // Spotify can take a moment to settle, especially when starting playback.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.refresh() }
    }

    func start() {
        guard !running else { return }
        running = true

        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(playbackChanged(_:)),
            name: notificationName, object: nil)

        // Spotify quitting or launching changes what we can do, and neither sends a playback
        // notification.
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        ws.addObserver(self, selector: #selector(appsChanged),
                       name: NSWorkspace.didTerminateApplicationNotification, object: nil)

        // Safety net only, and only while playing — see `tick`.
        let timer = Timer(timeInterval: 10, target: self, selector: #selector(tick),
                          userInfo: nil, repeats: true)
        timer.tolerance = 4
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer

        Log.write("spotify watcher started")
        refresh()
    }

    func stop() {
        guard running else { return }
        running = false
        DistributedNotificationCenter.default().removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        refreshTimer?.invalidate()
        refreshTimer = nil
        track = nil
        state = .stopped
        Log.write("spotify watcher stopped")
    }

    deinit { stop() }

    // MARK: Events

    @objc private func playbackChanged(_ note: Notification) {
        // The payload gives us the new state immediately, which is what makes the strip feel
        // instant; the follow-up Apple Event fills in artwork and volume.
        if let playerState = note.userInfo?["Player State"] as? String {
            state = SpotifyController.PlayerState(rawValue: playerState.lowercased()) ?? .unknown
        }
        refresh()
    }

    @objc private func appsChanged(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == SpotifyController.bundleID else { return }
        refresh()
    }

    @objc private func tick() {
        // Nothing playing means nothing to miss, so stay quiet rather than waking Spotify.
        guard state == .playing else { return }
        refresh()
    }

    // MARK: Refresh

    func refresh() {
        let availabilityNow = SpotifyController.availability()
        guard availabilityNow == .ready else {
            Log.writeIfChanged(key: "spotify-avail", "spotify unavailable: \(availabilityNow)")
            availability = availabilityNow
            track = nil
            state = .stopped
            return
        }
        // Apple Events are synchronous round trips to another process; off the main thread so
        // a busy or beachballed Spotify can never stall the overlay.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = SpotifyController.currentState()
            let failure = SpotifyController.lastFailure
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.availability = .ready
                    self.state = result.state
                    self.track = result.track
                    // Do not undo a volume the user has just set: Spotify's own rounding
                    // would otherwise nudge the slider by a point after every refresh.
                    if abs(result.volume - self.volume) > 1 { self.volume = result.volume }
                    Log.writeIfChanged(key: "spotify-now",
                                       "spotify \(result.state.rawValue): \(result.track.map { "\($0.name) — \($0.artist) [\($0.duration)s, art:\($0.artworkURL != nil)]" } ?? "no track"), vol \(result.volume)")
                } else {
                    self.availability = failure ?? .failed("no response")
                    self.track = nil
                }
            }
        }
    }
}
