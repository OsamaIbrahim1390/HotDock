import SwiftUI

/// Contents of the notch card: the script, a scrollbar, and the transport controls.
///
/// The slide is done here rather than by moving the window: the card is offset up by its own
/// height when hidden, so the window (which clips its content) hides it completely and it
/// appears to come out from behind the notch.
struct OverlayRootView: View {
    @ObservedObject var settings: Settings
    @ObservedObject var overlay: OverlayController
    /// Deliberately *not* observed here. `engine.offset` changes every frame while scrolling,
    /// and observing it would rebuild the whole card — background, border, clip shape and all —
    /// at the display's refresh rate. The subviews that need it observe it themselves.
    let engine: TeleprompterEngine
    @ObservedObject var notes: NoteStore
    @ObservedObject var spotify: SpotifyWatcher
    @ObservedObject var artwork: ArtworkLoader

    private var hiddenOffset: CGFloat { -(CGFloat(settings.overlayHeight) + 16) }

    var body: some View {
        card
            .offset(y: overlay.isRevealed ? 0 : hiddenOffset)
            .opacity(overlay.isRevealed ? 1 : 0)
            .animation(.spring(response: 0.38, dampingFraction: 0.80), value: overlay.isRevealed)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// Hairline between the card's columns.
    private var divider: some View {
        Rectangle()
            .fill(.white.opacity(0.10))
            .frame(width: 1)
            .padding(.vertical, 2)
    }

    private var card: some View {
        // Everything inside is driven off the card's real size, so resizing the overlay from
        // Settings rescales the padding, the control column and the scrollbar with it.
        GeometryReader { geo in
            let compact = geo.size.height < 120
            let pad: CGFloat = compact ? 9 : 12

            VStack(spacing: 6) {
            HStack(spacing: compact ? 5 : 7) {
                if overlay.isNoteMode {
                    InlineNoteEditor(store: notes, settings: settings,
                                     text: $overlay.noteDraft,
                                     isEditing: overlay.editingNoteID != nil,
                                     onSave: { overlay.saveNote() },
                                     onCancel: { overlay.cancelNote() })
                        .frame(maxWidth: .infinity)
                } else {
                    TeleprompterView(engine: engine, settings: settings)
                        .frame(maxWidth: .infinity)
                }

                if !overlay.isNoteMode {
                    ScriptScrollBar(engine: engine, width: compact ? 4 : 5)
                }

                if overlay.isDrawerOpen {
                    ScriptDrawer(engine: engine, settings: settings, overlay: overlay) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            overlay.isDrawerOpen = false
                        }
                    }
                    // Beside the script rather than over it: the drawer takes its own column
                    // and the text gives up the width, so you can still read while adjusting.
                    .frame(width: min(230, max(170, geo.size.width * 0.42)))
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                divider

                VStack(spacing: 0) {
                    ScriptControls(engine: engine,
                                   availableHeight: geo.size.height - pad * 2,
                                   drawerOpen: $overlay.isDrawerOpen,
                                   noteMode: $overlay.isNoteMode,
                                   playerVisible: $settings.playerVisible,
                                   showsPlayerToggle: settings.spotifyEnabled && spotify.showsPanel)
                        .fixedSize()
                    Spacer(minLength: 0)
                    StatusDot(engine: engine)
                }

                // The player gets its own column. It yields to the drawer, which is transient
                // and needs the width more.
                if settings.spotifyEnabled && settings.playerVisible
                    && !overlay.isDrawerOpen && spotify.showsPanel {
                    divider
                    SpotifyPlayerPanel(watcher: spotify, artwork: artwork)
                        .frame(width: min(190, max(116, geo.size.width * 0.3)))
                }
            }
            latestNotes
            }
            .padding(.horizontal, pad + 4)
            .padding(.vertical, pad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white.opacity(settings.textOpacity))
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.black.opacity(settings.backgroundOpacity))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

private extension OverlayRootView {
    /// The most recent note(s), pinned under the script. Useful for a line you want to keep in
    /// view — a name, a number you must not get wrong — without it scrolling away.
    @ViewBuilder
    var latestNotes: some View {
        if let problem = notes.syncProblem {
            Text(problem)
                .font(.system(size: 9))
                .foregroundStyle(.orange.opacity(0.85))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        let wanted = max(1, Int(settings.latestNoteCount))
        let recent = Array(notes.pinnedNotes.prefix(wanted))
        if settings.showLatestNote, !recent.isEmpty {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(recent) { note in
                    PinnedNoteRow(note: note,
                                  onOpen: { overlay.editNote(note) },
                                  onUnpin: { notes.unpin(noteID: note.id) })
                }
            }
            .padding(.top, 2)
        }
    }
}

/// One pinned note under the script: click it to reopen it in the editor, or unpin it.
private struct PinnedNoteRow: View {
    let note: Note
    let onOpen: () -> Void
    let onUnpin: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "pin.fill")
                .font(.system(size: 7))
                .foregroundStyle(.yellow.opacity(0.65))

            Text(note.text.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(hovering ? 0.85 : 0.62))
                .lineLimit(1)

            Spacer(minLength: 0)

            // Only on hover: a permanent row of close buttons under the script would be noise.
            if hovering {
                ControlButton(symbol: "xmark", label: "Unpin this note", size: 7, action: onUnpin)
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: onOpen)
        .help("Click to edit this note")
    }
}

/// Small, quiet indicator: filled while scrolling, hollow while paused. Enough to tell the two
/// apart at a glance without putting another control in front of the script.
private struct StatusDot: View {
    @ObservedObject var engine: TeleprompterEngine

    var body: some View {
        Circle()
            .fill(engine.isScrolling ? Color.green.opacity(0.85) : Color.clear)
            .overlay(Circle().strokeBorder(.white.opacity(0.3), lineWidth: 1))
            .frame(width: 5, height: 5)
    }
}
