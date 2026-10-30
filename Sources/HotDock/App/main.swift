import AppKit

// AppKit bootstrap rather than a SwiftUI `@main App`: the overlay needs a hand-built
// non-activating NSPanel, and an accessory (menu bar only) app is simpler to control here.
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
// Info.plist already sets LSUIElement, but setting this explicitly means the app also
// behaves correctly if the bare executable is run outside the .app bundle.
app.setActivationPolicy(.accessory)
app.run()
