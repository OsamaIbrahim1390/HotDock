import SwiftUI

/// Slides in over the script when you tap the drawer button: text size, and where to load a
/// script from. Everything here is something you set up *before* you start reading, which is
/// exactly why it is tucked away rather than sitting beside the text.
struct ScriptDrawer: View {
    @ObservedObject var engine: TeleprompterEngine
    @ObservedObject var settings: Settings
    @ObservedObject var overlay: OverlayController
    let onClose: () -> Void

    @State private var errorMessage: String?
    @State private var loadingNotes = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header

            // A ScrollView so the drawer stays usable at any card height: on a short overlay
            // the rows simply scroll rather than being clipped or squeezed.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 7) {
                    // Speed first: it is the one you reach for mid-read. A plain position
                    // slider is safe here — unlike the size control, changing speed does not
                    // move the drawer out from under the cursor.
                    sliderRow("gauge.with.dots.needle.50percent", "Scroll speed, points per second",
                              value: $settings.scrollSpeed, in: 5...300, step: 5)
                    sliderRow("textformat.size", "Text size",
                              value: $settings.fontSize, in: 9...48, step: 1)
                    OverlaySizeSlider(settings: settings, overlay: overlay)

                    drawerButton("doc.text", "Open text file…", action: openFile)
                    drawerButton("note.text", loadingNotes ? "Loading…" : "Load from Notes…",
                                 action: loadingNotes ? {} : openNotes)

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.system(size: 9))
                            .foregroundStyle(.orange.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Now loaded: \(engine.documentTitle)")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.black.opacity(0.55))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    /// Icon, slider and value on one line — the drawer is only ~200pt wide, so a written label
    /// would leave no room for the slider itself. The name lives in the tooltip.
    private func sliderRow(_ symbol: String, _ label: String, value: Binding<Double>,
                           in range: ClosedRange<Double>, step: Double) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 13)
            Slider(value: value, in: range, step: step)
                .controlSize(.mini)
            Text("\(Int(value.wrappedValue))")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 26, alignment: .trailing)
        }
        .help(label)
    }

    private var header: some View {
        HStack {
            Text("Script")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
            Spacer()
            ControlButton(symbol: "xmark", label: "Close", size: 9, action: onClose)
        }
    }

    private func drawerButton(_ symbol: String, _ title: String,
                              action: @escaping () -> Void) -> some View {
        DrawerButton(symbol: symbol, title: title, action: action)
    }

    // MARK: Actions

    private func openFile() {
        errorMessage = nil
        guard let picked = ScriptImporter.chooseTextFile() else { return }
        engine.load(ScriptDocument(text: picked.text), title: picked.title)
        onClose()
    }

    /// Notes can hold a lot of notes, and each name is a separate Apple Event, so the fetch
    /// happens off the main thread and the picker is a menu rather than another window.
    private func openNotes() {
        errorMessage = nil
        loadingNotes = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let notes = try ScriptImporter.listNotes()
                DispatchQueue.main.async {
                    loadingNotes = false
                    guard !notes.isEmpty else {
                        errorMessage = "No notes found."
                        return
                    }
                    presentNotesMenu(notes)
                }
            } catch {
                DispatchQueue.main.async {
                    loadingNotes = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func presentNotesMenu(_ notes: [ScriptImporter.NoteRef]) {
        let picker = MenuPicker()
        guard let chosen = picker.pick(notes, at: NSEvent.mouseLocation) else { return }
        load(noteID: chosen.id, title: chosen.name)
    }

    private func load(noteID: String, title: String) {
        guard !noteID.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let text = try ScriptImporter.noteText(id: noteID)
                DispatchQueue.main.async {
                    engine.load(ScriptDocument(text: text), title: title)
                    onClose()
                }
            } catch {
                DispatchQueue.main.async { errorMessage = error.localizedDescription }
            }
        }
    }
}


/// Wide labelled button for the drawer. Tap gesture rather than `Button`, for the same reason
/// as `ControlButton`: this panel never becomes key.
private struct DrawerButton: View {
    let symbol: String
    let title: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10))
            Text(title).font(.system(size: 10, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(.white.opacity(hovering ? 0.18 : 0.11))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}
