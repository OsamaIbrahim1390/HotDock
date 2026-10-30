import SwiftUI

/// The mini player as its own column on the right of the card: spinning record, what is
/// playing, and the transport controls together in one place.
///
/// Unlike the script's own controls this panel states its situation rather than vanishing —
/// a blank column where a player should be is more confusing than a line of text saying
/// Spotify is not running.
struct SpotifyPlayerPanel: View {
    @ObservedObject var watcher: SpotifyWatcher
    @ObservedObject var artwork: ArtworkLoader

    var body: some View {
        GeometryReader { geo in
            content(width: geo.size.width, height: geo.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: watcher.track?.artworkURL) { _, url in artwork.load(url) }
        .onAppear { artwork.load(watcher.track?.artworkURL) }
    }

    @ViewBuilder
    private func content(width: CGFloat, height: CGFloat) -> some View {
        switch watcher.availability {
        case .ready:
            if let track = watcher.track {
                player(track, width: width, height: height)
            } else {
                status("music.note", "Nothing playing")
            }
        case .notRunning, .notInstalled:
            // The column is not drawn at all in these cases — see `showsPanel`.
            EmptyView()
        case .permissionDenied:
            status("lock", "Not allowed to control Spotify. System Settings › Privacy & Security › Automation.")
        case .failed:
            EmptyView()
        }
    }

    private func status(_ symbol: String, _ message: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.3))
            Text(message)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(0.38))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }

    private func player(_ track: SpotifyController.Track,
                        width: CGFloat, height: CGFloat) -> some View {
        // The record takes whatever is left after the text and buttons, within reason.
        let disc = max(26, min(min(width * 0.62, height * 0.46), 64))
        let showsText = height >= 86
        let showsVolume = height >= 136

        return VStack(spacing: showsText ? 5 : 4) {
            SpotifyDisc(image: artwork.image, spinning: watcher.isPlaying)
                .frame(width: disc, height: disc)
                .contentShape(Circle())
                .onTapGesture { watcher.togglePlayPause() }
                .help("\(track.name) — \(track.artist)")

            if showsText {
                VStack(spacing: 0) {
                    Text(track.name)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                ControlButton(symbol: "backward.fill", label: "Previous track", size: 9) {
                    SpotifyController.previousTrack()
                    watcher.refresh()
                }
                ControlButton(symbol: watcher.isPlaying ? "pause.fill" : "play.fill",
                              label: watcher.isPlaying ? "Pause" : "Play", size: 11) {
                    watcher.togglePlayPause()
                }
                ControlButton(symbol: "forward.fill", label: "Next track", size: 9) {
                    SpotifyController.nextTrack()
                    watcher.refresh()
                }
            }

            if showsVolume && watcher.hasVolume {
                VolumeSlider(watcher: watcher)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 4)
    }
}

/// Volume.
///
/// Bound straight to the watcher, which now treats the value you set as the truth and only
/// accepts a correction from Spotify when it differs by more than its own rounding. That
/// removes the need for any local "while dragging" state, and with it the jumping thumb.
private struct VolumeSlider: View {
    @ObservedObject var watcher: SpotifyWatcher

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: watcher.volume <= 0 ? "speaker.slash.fill" : "speaker.fill")
                .font(.system(size: 7))
                .foregroundStyle(.white.opacity(0.35))
            Slider(value: Binding(
                get: { Double(max(0, watcher.volume)) },
                set: { watcher.setVolume(Int($0.rounded())) }
            ), in: 0...100, step: 1)
            .controlSize(.mini)
        }
        .opacity(watcher.hasVolume ? 1 : 0.4)
        .disabled(!watcher.hasVolume)
    }
}
