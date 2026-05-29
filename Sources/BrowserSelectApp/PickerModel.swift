import AppKit
import Combine

/// Observable state shared between the `AppDelegate` and the SwiftUI `PickerView`.
///
/// Holds the cached browser list (pre-warmed at launch) and the URL currently being
/// routed. The AppDelegate updates `pendingURL` when a URL-open event fires; the view
/// observes it and renders the picker. Selecting a browser calls back through `onOpen`.
@MainActor
final class PickerModel: ObservableObject {
    /// Cached, filtered, ordered browsers. Populated at launch and refreshed in the
    /// background so the first URL event meets the latency budget without a cold query.
    @Published var browsers: [DisplayBrowser] = []

    /// The URL awaiting a browser choice, or nil when the picker is idle/hidden.
    @Published var pendingURL: URL?

    /// Index of the keyboard-highlighted browser for arrow-key navigation.
    @Published var selectedIndex: Int = 0

    /// Invoked with the chosen browser and the pending URL when the user commits.
    var onOpen: ((DisplayBrowser, URL) -> Void)?

    /// Invoked when the user dismisses the picker without choosing (Escape / click-away).
    var onCancel: (() -> Void)?

    func open(_ browser: DisplayBrowser) {
        guard let url = pendingURL else { return }
        onOpen?(browser, url)
    }

    func cancel() {
        onCancel?()
    }
}
