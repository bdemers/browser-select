import AppKit
import BrowserSelectKit

/// A browser entry ready for display and launch. Wraps the kit's icon-free `Browser`
/// with an `NSImage` icon, and adds optional `launchArguments` so a single app (Chrome)
/// can be presented as several profile-specific choices.
struct DisplayBrowser: Identifiable {
    /// Unique per row. For a plain browser this is its bundle ID; for a Chrome profile it
    /// is `bundleID + "#" + profileDirectory` so multiple Chrome profiles stay distinct.
    let id: String
    /// Human-readable label (e.g. `"Google Chrome"` or `"Chrome — Work"`).
    let name: String
    /// The application bundle to launch.
    let url: URL
    /// The launched app's bundle identifier.
    let bundleID: String
    /// Icon shown in the picker.
    let icon: NSImage
    /// Extra command-line arguments passed to the app on launch (e.g.
    /// `["--profile-directory=Profile 11"]`). Empty for a normal launch.
    let launchArguments: [String]
}

/// Reads Google Chrome's installed profiles from its `Local State` file. Returns the
/// parsed, ordered profiles (see `ChromeProfiles`), or an empty array if Chrome has no
/// state on disk. File I/O lives here (app layer); the parsing is in the kit.
enum ChromeProfileService {
    /// Bundle ID of Google Chrome (the only browser for which profile support is wired up).
    static let chromeBundleID = "com.google.Chrome"

    private static let localStatePath =
        ("~/Library/Application Support/Google/Chrome/Local State" as NSString).expandingTildeInPath

    static func profiles() -> [ChromeProfile] {
        guard let data = FileManager.default.contents(atPath: localStatePath) else { return [] }
        return ChromeProfiles.parse(localStateJSON: data)
    }
}

/// Performs the framework-dependent half of browser enumeration: querying Launch
/// Services for apps that can open http URLs, then handing the raw candidates to the
/// pure `BrowserEnumerator` for self-exclusion, denylist filtering, de-dup, and ordering.
///
/// Uses `NSWorkspace.urlsForApplications(toOpen:)` (macOS 12+) — deliberately NOT the
/// deprecated `LSCopyApplicationURLsForURL`.
struct BrowserDiscovery {

    /// A representative http URL used purely to ask Launch Services "who can open this?".
    private static let probeURL = URL(string: "http://example.com")!

    private let enumerator: BrowserEnumerator

    /// - Parameter selfBundleID: This app's own bundle id, forwarded to the kit's
    ///   `BrowserEnumerator(excludingBundleID:)` so we never list ourselves.
    init(selfBundleID: String) {
        self.enumerator = BrowserEnumerator(excludingBundleID: selfBundleID)
    }

    /// Discovers installed browsers, filtered and ordered for the picker. When Chrome has
    /// more than one profile, its single entry is expanded into one entry per profile.
    ///
    /// Reads bundle metadata and icons on the calling thread, so callers should invoke
    /// this off the main thread for the background re-enumeration path.
    func discover() -> [DisplayBrowser] {
        let workspace = NSWorkspace.shared
        let appURLs = workspace.urlsForApplications(toOpen: Self.probeURL)

        var candidates: [Browser] = []
        var icons: [String: NSImage] = [:]

        for appURL in appURLs {
            guard let bundle = Bundle(url: appURL),
                  let bundleID = bundle.bundleIdentifier else { continue }

            let name = Self.displayName(for: appURL, bundle: bundle)
            candidates.append(Browser(url: appURL, bundleID: bundleID, name: name))
            if icons[bundleID] == nil {
                icons[bundleID] = workspace.icon(forFile: appURL.path)
            }
        }

        return enumerator.filter(candidates: candidates).flatMap { browser -> [DisplayBrowser] in
            let icon = icons[browser.bundleID] ?? workspace.icon(forFile: browser.url.path)
            return Self.entries(for: browser, icon: icon)
        }
    }

    /// Expands one filtered `Browser` into the picker rows it should produce. Normally a
    /// single row; for Chrome with 2+ profiles, one row per profile.
    private static func entries(for browser: Browser, icon: NSImage) -> [DisplayBrowser] {
        let plain = DisplayBrowser(
            id: browser.bundleID, name: browser.name, url: browser.url,
            bundleID: browser.bundleID, icon: icon, launchArguments: []
        )

        guard browser.bundleID == ChromeProfileService.chromeBundleID else { return [plain] }

        let profiles = ChromeProfileService.profiles()
        // Per the requirement: only break Chrome out into profiles when there's more than
        // one. Zero or one profile → a single, plain Chrome entry.
        guard profiles.count > 1 else { return [plain] }

        return profiles.map { profile in
            DisplayBrowser(
                id: "\(browser.bundleID)#\(profile.directory)",
                name: "\(browser.name) — \(profile.name)",
                url: browser.url,
                bundleID: browser.bundleID,
                icon: icon,
                launchArguments: ["--profile-directory=\(profile.directory)"]
            )
        }
    }

    /// Best-effort human-readable name: prefer the localized Finder display name,
    /// fall back to bundle display/name keys, then the file name without extension.
    private static func displayName(for url: URL, bundle: Bundle) -> String {
        if let localized = try? url.resourceValues(forKeys: [.localizedNameKey]).localizedName {
            return (localized as NSString).deletingPathExtension
        }
        if let display = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String {
            return display
        }
        if let name = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String {
            return name
        }
        return url.deletingPathExtension().lastPathComponent
    }
}
