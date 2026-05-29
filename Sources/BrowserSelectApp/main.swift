import AppKit

// Manual app bootstrap rather than @main/@NSApplicationMain: this is an LSUIElement
// accessory app launched from a hand-assembled bundle, and an explicit NSApplication
// setup keeps the entry point obvious and avoids storyboard/main-nib assumptions.
//
// Top-level code in main.swift runs on the main thread; assumeIsolated lets us touch
// the main-actor-isolated AppDelegate without spuriously crossing actor boundaries.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate

    // .accessory matches LSUIElement = YES in Info.plist: no Dock icon, no menu bar, but
    // the process stays resident so only the first post-reboot URL click pays a cold start.
    app.setActivationPolicy(.accessory)
    app.run()
}
