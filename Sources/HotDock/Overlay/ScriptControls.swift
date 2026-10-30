import SwiftUI

/// Transport controls down the right-hand side of the overlay.
///
/// Deliberately minimal. Anything not needed mid-sentence while reading lives in the drawer,
/// Settings or the menu bar — a row of small icons next to the script is a distraction you do
/// not want while presenting.
struct ScriptControls: View {
    @ObservedObject var engine: TeleprompterEngine
    /// Height available for the column, so spacing can breathe on a taller card.
    let availableHeight: CGFloat
    @Binding var drawerOpen: Bool
    @Binding var noteMode: Bool
    @Binding var playerVisible: Bool
    /// Only offer the player toggle when there is a player to toggle.
    let showsPlayerToggle: Bool

    private var spacing: CGFloat { availableHeight < 120 ? 7 : 10 }

    var body: some View {
        VStack(spacing: spacing) {
            ControlButton(symbol: engine.isPlaying ? "pause.fill" : "play.fill",
                          label: engine.isPlaying ? "Pause" : "Play") {
                engine.togglePlay()
            }
            ControlButton(symbol: "arrow.counterclockwise", label: "Start again") {
                engine.restart()
            }
            ControlButton(symbol: noteMode ? "xmark" : "square.and.pencil",
                          label: noteMode ? "Close note" : "Take a note") {
                noteMode.toggle()
            }
            ControlButton(symbol: drawerOpen ? "chevron.right" : "slider.horizontal.3",
                          label: drawerOpen ? "Close drawer" : "Text size and loading a script") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                    drawerOpen.toggle()
                }
            }
            if showsPlayerToggle {
                ControlButton(symbol: "music.note",
                              label: playerVisible ? "Hide the player" : "Show the player",
                              isActive: playerVisible) {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        playerVisible.toggle()
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A tap-gesture button rather than a SwiftUI `Button`.
///
/// The overlay is a non-activating panel that never becomes key, which is exactly the
/// situation where `Button`'s focus-aware machinery is unreliable. A plain hit-tested tap
/// gesture has no such dependency. `@State` also cannot live in a `ButtonStyle` — it is not a
/// `View`, so it gets no storage — which is the other reason the previous version was fragile.
struct ControlButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 11
    /// Draws the button lit, for toggles that are currently on.
    var isActive: Bool = false
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .semibold))
            .frame(width: 20, height: 17)
            .foregroundStyle(.white.opacity(hovering || isActive ? 0.95 : 0.6))
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(.white.opacity(hovering ? 0.18 : (isActive ? 0.12 : 0)))
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .help(label)
            .accessibilityLabel(label)
    }
}
