import SwiftUI

/// The note editor that replaces the script inside the overlay card.
///
/// Same window, no second panel: tap the pencil and the script gives way to a blank sheet.
struct InlineNoteEditor: View {
    @ObservedObject var store: NoteStore
    @ObservedObject var settings: Settings
    @Binding var text: String
    let isEditing: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 9))
                    .foregroundStyle(.yellow.opacity(0.7))
                Text(isEditing ? "Editing note" : (store.currentSession?.title ?? "New session"))
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(isEditing ? "↩ update · empty to delete · esc"
                               : (settings.syncToNotesApp ? "↩ save to Notes · esc" : "↩ save · esc"))
                    .font(.system(size: 9, design: .rounded))
                    .foregroundStyle(.white.opacity(0.32))
                    .fixedSize()
            }

            NoteTextView(text: $text, fontSize: max(12, settings.fontSize * 0.75),
                         onSave: onSave, onCancel: onCancel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
