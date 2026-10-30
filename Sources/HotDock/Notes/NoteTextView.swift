import AppKit
import SwiftUI

/// Text field for the quick-note panel.
///
/// A hand-rolled `NSTextView` rather than SwiftUI's `TextEditor` because the key handling has
/// to be exact: Return saves, Shift/Option-Return inserts a newline, Escape dismisses. Those
/// keys are ones `TextEditor` wants for itself, and this panel is the one place in the app
/// where a swallowed keystroke means a lost thought mid-interview.
struct NoteTextView: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat
    let onSave: () -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let textView = KeyCatchingTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: fontSize)
        textView.textColor = .white
        textView.insertionPointColor = .white
        textView.textContainerInset = NSSize(width: 2, height: 4)
        textView.onSave = onSave
        textView.onCancel = onCancel

        let scroll = NSScrollView()
        scroll.documentView = textView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.autohidesScrollers = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? KeyCatchingTextView else { return }
        if textView.string != text { textView.string = text }
        textView.font = .systemFont(ofSize: fontSize)
        textView.onSave = onSave
        textView.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        private let text: Binding<String>
        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}

final class KeyCatchingTextView: NSTextView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 53:                                   // Escape
            onCancel?()
        case 36, 76:                               // Return, numeric Enter
            // Shift or Option gives you a newline; everything else saves, including Cmd-Return.
            if flags.contains(.shift) || flags.contains(.option) {
                super.keyDown(with: event)
            } else {
                onSave?()
            }
        default:
            super.keyDown(with: event)
        }
    }
}
