// GhostOverlay — stealth AI-assistant overlay. Entry point.
import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(Config.debug ? .regular : .accessory)
app.run()
