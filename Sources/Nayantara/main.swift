import AppKit

// Plain AppKit entry point. A SwiftUI App needs at least one scene, and an
// empty Settings scene still shows up as a stray window; everything this app
// shows is AppKit-hosted (StatusItem.swift, DetachedWindow.swift) anyway.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)   // menu bar only, no Dock icon
    app.run()
}
