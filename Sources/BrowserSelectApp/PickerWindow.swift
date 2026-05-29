import AppKit
import SwiftUI

/// A borderless, floating window that hosts the SwiftUI `PickerView`.
///
/// Created hidden at launch (pre-warm) so the first URL event only has to position and
/// reveal it — no view-hierarchy construction on the hot path. The window resigns key
/// and hides itself when it loses focus, which doubles as a click-away cancel.
final class PickerWindow: NSWindow {

    private let model: PickerModel
    /// Typed reference to the SwiftUI host so `present()` can size to its fitting size
    /// without a fragile `contentView as? NSHostingView<…>` cast.
    private let hosting: NSHostingView<PickerView>

    init(model: PickerModel) {
        self.model = model
        self.hosting = NSHostingView(rootView: PickerView(model: model))
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        // Borderless: no title bar means no safe-area inset and frame == content view, so
        // the window sizes exactly to the SwiftUI content (no leftover whitespace). The
        // rounded-card look + shadow that the titled window used to provide is now drawn by
        // PickerView's RoundedRectangle background over a transparent window.
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .transient]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false

        contentView = hosting
    }

    /// Borderless-style windows must opt in to becoming key to receive keyboard events.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Centers and reveals the picker, making it key so keyboard nav works immediately.
    func present() {
        // Size the window to exactly fit the SwiftUI content for the current browser/profile
        // count, so there is no leftover whitespace and the margins stay symmetric. The
        // window is borderless, so frame == content view (no title bar / safe-area inset) and
        // the fitting size maps 1:1 onto the window.
        hosting.layoutSubtreeIfNeeded()
        var frame = self.frame
        frame.size = hosting.fittingSize
        setFrame(frame, display: false)
        center()
        makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Hides the picker and clears routing state.
    func dismiss() {
        orderOut(nil)
        model.pendingURL = nil
        model.selectedIndex = 0
    }

    /// Treat losing key status as a cancel (click-away dismissal).
    override func resignKey() {
        super.resignKey()
        if isVisible { model.cancel() }
    }
}
