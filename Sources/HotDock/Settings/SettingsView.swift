import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: Settings

    var body: some View {
        Form {
            Section("Overlay size") {
                slider("Width", value: $settings.overlayWidth, in: 280...1200, step: 10, unit: "pt")
                slider("Height", value: $settings.overlayHeight, in: 70...600, step: 5, unit: "pt")
                Button("Reset to \(Int(Settings.defaultOverlayWidth))×\(Int(Settings.defaultOverlayHeight))") {
                    settings.resetOverlaySize()
                }
                Text("Everything inside the overlay — padding, scrollbar and the control column — scales with these. Below about 120 pt tall the controls thin out to leave room for the script.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Script") {
                Picker("Typeface", selection: $settings.scriptFont) {
                    ForEach(ScriptFont.allCases, id: \.self) { font in
                        Text(font.title).tag(font)
                    }
                }
                slider("Text size", value: $settings.fontSize, in: 9...48, step: 1, unit: "pt")
                slider("Line spacing", value: $settings.lineSpacing, in: 0...16, step: 0.5, unit: "pt")
                slider("Speed", value: $settings.scrollSpeed, in: 5...300, step: 5, unit: "pt/sec")
                slider("Trackpad scrolling", value: $settings.wheelSensitivity,
                       in: 0.25...3, step: 0.05, unit: "×")
                Text("Scroll with two fingers over the script to move through it by hand. 1.0× moves the text exactly with your fingers, like any other document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Appearance") {
                slider("Background opacity", value: $settings.backgroundOpacity, in: 0.1...1, step: 0.02, percent: true)
                slider("Text opacity", value: $settings.textOpacity, in: 0.3...1, step: 0.02, percent: true)
            }

            Section("Reveal") {
                Picker("When hidden", selection: $settings.revealMode) {
                    ForEach(RevealMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                slider("Trigger margin", value: $settings.revealMargin, in: 0...200, step: 5, unit: "pt")
                slider("Reveal delay", value: $settings.revealDelay, in: 0...1, step: 0.05, unit: "sec")
                slider("Hide delay", value: $settings.hideDelay, in: 0...2, step: 0.05, unit: "sec")
                Text("The trigger area is the notch plus this margin either side. Keeping it narrow stops an app's menu titles from revealing the overlay by accident.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notes") {
                Toggle("Show the latest note on the overlay", isOn: $settings.showLatestNote)
                slider("How many", value: $settings.latestNoteCount, in: 1...3, step: 1, unit: "")
                    .disabled(!settings.showLatestNote)
                Toggle("Also save notes to the Notes app", isOn: $settings.syncToNotesApp)
                Text("Notes are always written to a Markdown file in Application Support first — that needs no permission and cannot half-fail. With this on they are also mirrored into a \"HotDock\" folder in Notes, one note per session. macOS will ask permission the first time.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Spotify mini player") {
                Toggle("Show what Spotify is playing", isOn: $settings.spotifyEnabled)
                Text("Controls the Spotify app on this Mac through Apple Events — no account, no web API. macOS will ask permission the first time. HotDock never launches Spotify, and hides the strip while a script is playing. Album artwork is the only thing this app ever downloads. Track controls and volume are in the menu bar.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notch glow") {
                Toggle("Show Siri glow around the notch", isOn: $settings.showNotchGlow)
                Picker("During full-screen video", selection: $settings.fullScreenGlow) {
                    ForEach(FullScreenGlowBehavior.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .disabled(!settings.showNotchGlow)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
    }

    private func slider(_ label: String, value: Binding<Double>,
                        in range: ClosedRange<Double>, step: Double,
                        unit: String = "", percent: Bool = false) -> some View {
        HStack {
            Text(label)
            Slider(value: value, in: range, step: step)
            Text(percent ? "\(Int(value.wrappedValue * 100))%"
                         : "\(formatted(value.wrappedValue)) \(unit)")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)
        }
    }

    private func formatted(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : String(format: "%.1f", value)
    }
}
