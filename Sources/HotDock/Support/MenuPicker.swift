import AppKit

/// Pops up a list and returns what was chosen.
///
/// `NSMenu.popUp(positioning:at:in:)` runs its own modal loop and returns a plain Bool, and
/// `highlightedItem` is already nil by then — so the selection has to be captured by the
/// item's action while the menu is still up.
final class MenuPicker: NSObject {

    private var chosen: ScriptImporter.NoteRef?

    func pick(_ notes: [ScriptImporter.NoteRef], at point: NSPoint) -> ScriptImporter.NoteRef? {
        chosen = nil
        let menu = NSMenu()
        for note in notes {
            let item = NSMenuItem(title: note.name.isEmpty ? "(untitled)" : note.name,
                                  action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = note
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: point, in: nil)
        return chosen
    }

    @objc private func choose(_ sender: NSMenuItem) {
        chosen = sender.representedObject as? ScriptImporter.NoteRef
    }
}
