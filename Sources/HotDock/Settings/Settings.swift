import SwiftUI

/// How the overlay decides to be on screen.
enum RevealMode: String, CaseIterable {
    /// Hidden behind the notch; slides down when the cursor reaches the notch area.
    case hover
    /// Always on screen. What you want while actually reading a script.
    case always

    var title: String {
        switch self {
        case .hover: return "Reveal on Hover"
        case .always: return "Always Visible"
        }
    }
}

/// Typeface for the script. A small, deliberate set rather than every font on the Mac:
/// these are the ones that stay legible at a glance from a metre away.
enum ScriptFont: String, CaseIterable {
    case rounded, standard, serif, monospaced

    var title: String {
        switch self {
        case .rounded: return "Rounded"
        case .standard: return "System"
        case .serif: return "Serif"
        case .monospaced: return "Monospaced"
        }
    }

    var design: Font.Design {
        switch self {
        case .rounded: return .rounded
        case .standard: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

/// What the notch glow does while a video is playing full-screen.
enum FullScreenGlowBehavior: String, CaseIterable {
    /// Glow disappears completely. Default: nothing of ours on screen during a film.
    case hide
    /// Outline stays but is drawn near-black, so it reads as part of the bezel.
    case dark
    /// Leave the Siri glow running regardless.
    case ignore

    var title: String {
        switch self {
        case .hide: return "Hide Glow During Full-Screen Video"
        case .dark: return "Dark Outline During Full-Screen Video"
        case .ignore: return "Keep Glow During Full-Screen Video"
        }
    }
}

/// Single source of truth for user preferences, backed by UserDefaults so everything
/// survives a relaunch. Grows as features land; keys are never renamed once shipped.
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    static let defaultOverlayWidth = 560.0
    static let defaultOverlayHeight = 190.0

    /// Escape hatch: shrink the overlay too far and its own controls become unusable, so this
    /// is reachable from the menu bar as well as the drawer.
    func resetOverlaySize() {
        overlayWidth = Self.defaultOverlayWidth
        overlayHeight = Self.defaultOverlayHeight
    }

    // MARK: Overlay appearance

    @Published var overlayWidth: Double { didSet { save(overlayWidth, "overlayWidth") } }
    @Published var overlayHeight: Double { didSet { save(overlayHeight, "overlayHeight") } }
    @Published var backgroundOpacity: Double { didSet { save(backgroundOpacity, "backgroundOpacity") } }
    @Published var textOpacity: Double { didSet { save(textOpacity, "textOpacity") } }

    /// Master switch: is the overlay in play at all (menu bar "Enable Overlay").
    @Published var overlayEnabled: Bool { didSet { save(overlayEnabled, "overlayEnabled") } }
    /// Siri-coloured sheen around the notch outline, so you can tell at a glance HotDock is live.
    @Published var showNotchGlow: Bool { didSet { save(showNotchGlow, "showNotchGlow") } }
    /// How the glow behaves while a video is playing full-screen.
    @Published var fullScreenGlow: FullScreenGlowBehavior { didSet { save(fullScreenGlow.rawValue, "fullScreenGlow") } }

    // MARK: Teleprompter

    /// Points per second.
    @Published var scrollSpeed: Double { didSet { save(scrollSpeed, "scrollSpeed") } }
    @Published var fontSize: Double { didSet { save(fontSize, "fontSize") } }
    @Published var lineSpacing: Double { didSet { save(lineSpacing, "lineSpacing") } }
    @Published var scriptFont: ScriptFont { didSet { save(scriptFont.rawValue, "scriptFont") } }
    /// How far the script moves per unit of trackpad scrolling. 1.0 matches the rest of macOS.
    @Published var wheelSensitivity: Double { didSet { save(wheelSensitivity, "wheelSensitivity") } }

    // MARK: Notes

    /// Show the most recent note(s) along the bottom of the overlay.
    @Published var showLatestNote: Bool { didSet { save(showLatestNote, "showLatestNote") } }
    @Published var latestNoteCount: Double { didSet { save(latestNoteCount, "latestNoteCount") } }
    /// Mirror each note into the Notes app, in a "HotDock" folder, one note per session.
    @Published var syncToNotesApp: Bool { didSet { save(syncToNotesApp, "syncToNotesApp") } }

    // MARK: Spotify

    /// Off by default. Turning it on starts the watcher and, on first use, asks macOS for
    /// permission to control Spotify.
    @Published var spotifyEnabled: Bool { didSet { save(spotifyEnabled, "spotifyEnabled") } }
    /// Whether the player column is currently showing. Toggled from the card, and remembered.
    @Published var playerVisible: Bool { didSet { save(playerVisible, "playerVisible") } }

    // MARK: Reveal behaviour

    @Published var revealMode: RevealMode { didSet { save(revealMode.rawValue, "revealMode") } }
    /// Extra width either side of the notch that still counts as the reveal zone. Keeping this
    /// small means an app's menu titles do not accidentally trigger a reveal.
    @Published var revealMargin: Double { didSet { save(revealMargin, "revealMargin") } }
    /// Cursor must sit in the zone this long before revealing, so merely sweeping across the
    /// menu bar on the way somewhere else does nothing.
    @Published var revealDelay: Double { didSet { save(revealDelay, "revealDelay") } }
    /// Grace period after the cursor leaves before it slides away again.
    @Published var hideDelay: Double { didSet { save(hideDelay, "hideDelay") } }

    private init() {
        defaults.register(defaults: [
            "overlayWidth": Self.defaultOverlayWidth,
            "overlayHeight": Self.defaultOverlayHeight,
            "backgroundOpacity": 0.82,
            "textOpacity": 1.0,
            "overlayEnabled": true,
            "showNotchGlow": true,
            "fullScreenGlow": FullScreenGlowBehavior.hide.rawValue,
            "revealMode": RevealMode.hover.rawValue,
            "scrollSpeed": 40.0,
            "fontSize": 19.0,
            "lineSpacing": 3.0,
            "scriptFont": ScriptFont.rounded.rawValue,
            "wheelSensitivity": 1.0,
            "showLatestNote": true,
            "latestNoteCount": 1.0,
            "syncToNotesApp": true,
            "spotifyEnabled": false,
            "playerVisible": true,
            "revealMargin": 40.0,
            "revealDelay": 0.10,
            "hideDelay": 0.45,
        ])
        overlayWidth = defaults.double(forKey: "overlayWidth")
        overlayHeight = defaults.double(forKey: "overlayHeight")
        backgroundOpacity = defaults.double(forKey: "backgroundOpacity")
        textOpacity = defaults.double(forKey: "textOpacity")
        overlayEnabled = defaults.bool(forKey: "overlayEnabled")
        showNotchGlow = defaults.bool(forKey: "showNotchGlow")
        fullScreenGlow = FullScreenGlowBehavior(rawValue: defaults.string(forKey: "fullScreenGlow") ?? "") ?? .hide
        revealMode = RevealMode(rawValue: defaults.string(forKey: "revealMode") ?? "") ?? .hover
        scrollSpeed = defaults.double(forKey: "scrollSpeed")
        fontSize = defaults.double(forKey: "fontSize")
        lineSpacing = defaults.double(forKey: "lineSpacing")
        scriptFont = ScriptFont(rawValue: defaults.string(forKey: "scriptFont") ?? "") ?? .rounded
        wheelSensitivity = defaults.double(forKey: "wheelSensitivity")
        showLatestNote = defaults.bool(forKey: "showLatestNote")
        latestNoteCount = defaults.double(forKey: "latestNoteCount")
        syncToNotesApp = defaults.bool(forKey: "syncToNotesApp")
        spotifyEnabled = defaults.bool(forKey: "spotifyEnabled")
        playerVisible = defaults.bool(forKey: "playerVisible")
        revealMargin = defaults.double(forKey: "revealMargin")
        revealDelay = defaults.double(forKey: "revealDelay")
        hideDelay = defaults.double(forKey: "hideDelay")
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: key) }
}
