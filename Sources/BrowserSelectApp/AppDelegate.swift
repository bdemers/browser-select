import AppKit
import BrowserSelectKit
import os

/// Wires the macOS app together:
/// 1. Registers the `kAEGetURL` Apple Event handler so opened http/https URLs arrive here.
/// 2. Pre-warms the browser cache and the hidden picker window at launch (latency budget).
/// 3. Routes incoming URLs through `URLRouter`, shows the picker, and launches the choice.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private let model = PickerModel()
    private var pickerWindow: PickerWindow!
    private var discovery: BrowserDiscovery!

    /// This app's own bundle URL, used as a belt-and-suspenders self-exclusion check on
    /// the launch path in case `Bundle.main.bundleIdentifier` is nil/empty and the
    /// bundle-ID-based filter in `BrowserEnumerator` can't identify us.
    private let selfBundleURL = Bundle.main.bundleURL

    private let log = Logger(subsystem: "com.bdemers.browserselect", category: "routing")

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        discovery = BrowserDiscovery(selfBundleID: selfBundleID)

        // Pre-warm the browser list synchronously so the cache is populated BEFORE the
        // URL handler can fire. urlsForApplications is fast; doing it inline guarantees
        // the first event never races an empty list.
        model.browsers = discovery.discover()

        model.onOpen = { [weak self] browser, url in
            self?.launch(url, in: browser)
        }
        model.onCancel = { [weak self] in
            self?.pickerWindow.dismiss()
        }

        // Build the picker window now (hidden). Constructing the view hierarchy here keeps
        // it off the hot path; the first URL event only needs to position + reveal it.
        pickerWindow = PickerWindow(model: model)

        // Register for URL-open Apple Events (kInternetEventClass / kAEGetURL). The
        // CFBundleURLTypes entry in Info.plist makes Launch Services deliver these to us.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        // Background refresh to catch browser installs/uninstalls without re-launching.
        scheduleBackgroundRefresh()
    }

    /// Apple Event entry point for an opened URL. Validates via `URLRouter`, then presents
    /// the picker (or silently drops the event if the URL is malformed/disallowed).
    @objc func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        let start = DispatchTime.now()
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URLRouter.sanitize(raw)
        else {
            return
        }
        model.pendingURL = url
        model.selectedIndex = 0
        pickerWindow.present()

        // Instrument the receive→present hot path so the <300 ms design budget can be
        // confirmed on the user's own machine (see README "Manual Verification"). Scheme
        // only — never the full URL — to avoid logging secrets.
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        log.info(
            // swiftlint:disable:next line_length
            "Picker presented in \(elapsedMs, format: .fixed(precision: 1), privacy: .public) ms for scheme \(url.scheme ?? "?", privacy: .public)"
        )
    }

    /// Launches the sanitized URL in the chosen browser, then hides the picker.
    private func launch(_ url: URL, in browser: DisplayBrowser) {
        // Defense in depth: never open a URL in ourselves even if bundle-ID exclusion
        // failed (e.g. Bundle.main.bundleIdentifier was nil → excluded ID was ""). Compare
        // standardized file URLs so symlink/trailing-slash differences don't slip through.
        guard browser.url.standardizedFileURL != selfBundleURL.standardizedFileURL else {
            log.error("Refusing to open URL in BrowserSelect itself; dismissing picker")
            pickerWindow.dismiss()
            return
        }

        if browser.launchArguments.isEmpty {
            launchViaWorkspace(url, in: browser)
        } else {
            launchWithArguments(url, in: browser)
        }
        pickerWindow.dismiss()
    }

    /// Standard launch: hand the URL to Launch Services to open in the chosen app.
    private func launchViaWorkspace(_ url: URL, in browser: DisplayBrowser) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(
            [url],
            withApplicationAt: browser.url,
            configuration: config
        ) { [weak self] _, error in
            if let error {
                // Log scheme+host only — never the full URL. Path/query/fragment can carry
                // OAuth tokens or other secrets that must not reach the unified log. Static
                // format string with privacy-aware interpolation (no untyped NSLog variadic).
                let scheme = url.scheme ?? "?"
                let host = url.host ?? "?"
                self?.log.error(
                    // swiftlint:disable:next line_length
                    "Failed to open \(scheme, privacy: .public)://\(host, privacy: .private) in \(browser.name, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    /// Argument-bearing launch (e.g. a Chrome profile via `--profile-directory=`).
    ///
    /// `NSWorkspace.OpenConfiguration.arguments` are only honored when the app is launched
    /// cold; if Chrome is already running they are ignored and the URL lands in whatever
    /// profile was last active. Executing the app's binary directly with the arguments lets
    /// the running instance route the URL to the requested profile. The URL is the
    /// already-sanitized http/https URL and the arguments are passed as a literal argv
    /// array (no shell), so there is no injection surface.
    private func launchWithArguments(_ url: URL, in browser: DisplayBrowser) {
        guard let bundle = Bundle(url: browser.url),
            let exeName = bundle.object(forInfoDictionaryKey: "CFBundleExecutable") as? String
        else {
            // Fall back to a normal open if we can't locate the executable.
            launchViaWorkspace(url, in: browser)
            return
        }
        let exeURL = browser.url
            .appendingPathComponent("Contents/MacOS", isDirectory: true)
            .appendingPathComponent(exeName)

        let process = Process()
        process.executableURL = exeURL
        process.arguments = browser.launchArguments + [url.absoluteString]
        do {
            try process.run()
        } catch {
            log.error(
                // swiftlint:disable:next line_length
                "Profile launch failed for \(browser.name, privacy: .public): \(error.localizedDescription, privacy: .public); falling back to default open"
            )
            launchViaWorkspace(url, in: browser)
        }
    }

    /// Re-enumerates browsers off the main thread every 30s so the cache tracks
    /// installs/uninstalls. Cheap and idempotent; results are swapped in on the main actor.
    private func scheduleBackgroundRefresh() {
        // Capture the discovery value (a struct) so the background closure does not touch
        // any main-actor-isolated state; only the result hand-off hops back to the main actor.
        let discovery = self.discovery!
        let model = self.model
        let timer = Timer(timeInterval: 30, repeats: true) { _ in
            DispatchQueue.global(qos: .utility).async {
                let fresh = discovery.discover()
                Task { @MainActor in model.browsers = fresh }
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}
