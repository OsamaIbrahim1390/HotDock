import AppKit

/// Talks to the Spotify desktop app over Apple Events, and nothing else.
///
/// No Web API, no account, no network: every call here is a local Apple Event to an app
/// already running on this Mac. The only thing that ever leaves the machine is the album
/// artwork image fetch, and only when the player is switched on.
///
/// It deliberately never launches Spotify. `NSAppleScript` would happily start it, which is
/// the last thing you want from an overlay that is meant to stay out of the way.
enum SpotifyController {

    static let bundleID = "com.spotify.client"

    enum PlayerState: String {
        case playing, paused, stopped, unknown
    }

    struct Track: Equatable {
        var name: String
        var artist: String
        var album: String
        var artworkURL: String?
        var duration: Int      // seconds
    }

    enum Availability: Equatable {
        case ready
        case notInstalled
        case notRunning
        case permissionDenied
        case failed(String)
    }

    // MARK: Availability

    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }

    static var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    /// Checked in order, cheapest first, so a missing or closed Spotify never produces a
    /// permission prompt or an Apple Event timeout.
    static func availability() -> Availability {
        guard isInstalled else { return .notInstalled }
        guard isRunning else { return .notRunning }
        return .ready
    }

    // MARK: Reading

    static func currentState() -> (state: PlayerState, track: Track?, volume: Int)? {
        guard availability() == .ready else { return nil }
        // One script for everything: a separate Apple Event per property would be several
        // round trips to another process on every update.
        //
        // `using terms from` is what makes `tell application id` work. Targeting by bundle id
        // is right at runtime (it does not care where Spotify lives or what it is called), but
        // the compiler cannot resolve "player state" or "current track" from an id alone.
        //
        // Also: no intermediate variables. `st` in particular is reserved by Spotify's own
        // terminology and fails to compile, which the compile check caught.
        let source = """
        using terms from application "Spotify"
            tell application id "\(bundleID)"
                if player state is stopped then return "stopped" & tab & "" & tab & "" & tab & "" & tab & "" & tab & "0" & tab & (sound volume as text)
                return (player state as text) & tab & (name of current track) & tab & (artist of current track) & tab & (album of current track) & tab & (artwork url of current track) & tab & (duration of current track as text) & tab & (sound volume as text)
            end tell
        end using terms from
        """
        guard let raw = run(source)?.stringValue else { return nil }
        let parts = raw.components(separatedBy: "\t")
        guard parts.count >= 7 else {
            if parts.first == "stopped" { return (.stopped, nil, Int(parts.last ?? "") ?? 0) }
            return nil
        }
        let state = PlayerState(rawValue: parts[0]) ?? .unknown
        // Spotify reports duration in milliseconds despite the dictionary saying seconds.
        let rawDuration = Int(parts[5]) ?? 0
        let track = Track(name: parts[1],
                          artist: parts[2],
                          album: parts[3],
                          artworkURL: parts[4].isEmpty ? nil : parts[4],
                          duration: rawDuration > 10_000 ? rawDuration / 1000 : rawDuration)
        return (state, track, Int(parts[6]) ?? 0)
    }

    // MARK: Commands

    static func playPause() { command("playpause") }
    static func nextTrack() { command("next track") }
    static func previousTrack() { command("previous track") }

    static func currentVolume() -> Int? {
        guard availability() == .ready else { return nil }
        guard let raw = run(wrapped("return (sound volume as text)"))?.stringValue else { return nil }
        return Int(raw)
    }

    static func setVolume(_ value: Int) {
        guard availability() == .ready else { return }
        let clamped = min(100, max(0, value))
        _ = run(wrapped("set sound volume to \(clamped)"))
    }

    private static func command(_ verb: String) {
        guard availability() == .ready else { return }
        _ = run(wrapped("\(verb)"))
    }

    /// Targets Spotify by bundle id while letting the compiler load its terminology by name.
    private static func wrapped(_ body: String) -> String {
        """
        using terms from application "Spotify"
            tell application id "\(bundleID)" to \(body)
        end using terms from
        """
    }

    // MARK: Apple Events

    /// Set when Spotify automation is refused, so the UI can explain rather than going quiet.
    private(set) static var lastFailure: Availability?

    @discardableResult
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var error: NSDictionary?
        let result = script.executeAndReturnError(&error)
        if let error {
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            switch code {
            case -1743:                       // not authorised to send Apple Events
                lastFailure = .permissionDenied
            case -600, -609:                  // application isn't running / connection invalid
                lastFailure = .notRunning
            default:
                lastFailure = .failed(error[NSAppleScript.errorMessage] as? String ?? "error \(code)")
            }
            Log.writeIfChanged(key: "spotify-error", "spotify apple event failed: \(code)")
            return nil
        }
        lastFailure = nil
        return result
    }
}
