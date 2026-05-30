import Foundation

/// Filters and orders a set of candidate browser apps for presentation in the picker.
///
/// The framework-dependent discovery step (querying Launch Services via
/// `NSWorkspace.urlsForApplications(toOpen:)`) lives in the app target. This type
/// owns only the *pure* part: excluding this app itself, de-duplicating bundle IDs,
/// and producing a stable sort order. Keeping it AppKit-free is deliberate — it lets
/// the self-exclusion and de-dup logic be exercised by `swift test` with no UI session.
///
/// Self-exclusion uses an **injected** bundle identifier rather than reading
/// `Bundle.main.bundleIdentifier`, so tests can pass a synthetic ID and assert the
/// candidate is removed. The app's call site supplies the real value.
public struct BrowserEnumerator {

    /// Bundle IDs that register as http/https handlers but are **not** web browsers.
    ///
    /// Some apps (notably terminals) claim the http/https URL schemes — and even the
    /// `com.apple.default-app.web-browser` role — so Launch Services lists them as
    /// default-browser candidates. They are not browsers and should never appear in the
    /// picker. macOS provides no API that distinguishes them, so we filter by a curated
    /// denylist. Extend this set if other non-browsers leak in.
    public static let defaultDenylist: Set<String> = [
        "com.googlecode.iterm2",  // iTerm
        "com.apple.Terminal",  // Terminal
    ]

    /// The bundle identifier to exclude from results (this app's own ID).
    private let excludedBundleID: String

    /// Bundle IDs filtered out as known non-browsers (see `defaultDenylist`).
    private let denylistedBundleIDs: Set<String>

    /// - Parameters:
    ///   - excludingBundleID: Bundle ID removed from any candidate list so BrowserSelect
    ///     never offers to open URLs in itself (which would loop forever).
    ///   - denylist: Bundle IDs to drop as known non-browsers. Defaults to
    ///     `defaultDenylist`; injectable so tests can supply their own set.
    public init(excludingBundleID: String, denylist: Set<String> = BrowserEnumerator.defaultDenylist) {
        self.excludedBundleID = excludingBundleID
        self.denylistedBundleIDs = denylist
    }

    /// Filters raw candidates into the list shown to the user.
    ///
    /// - Parameter candidates: Browsers discovered by the app's Launch Services query,
    ///   in Launch Services' preference order.
    /// - Returns: Candidates with this app excluded, known non-browsers (denylist) removed,
    ///   duplicate bundle IDs collapsed (first occurrence wins, preserving Launch Services
    ///   order), and the remainder sorted case-insensitively by display name for a
    ///   predictable picker layout.
    public func filter(candidates: [Browser]) -> [Browser] {
        var seen = Set<String>()
        let deduped = candidates.filter { browser in
            guard browser.bundleID != excludedBundleID else { return false }
            guard !denylistedBundleIDs.contains(browser.bundleID) else { return false }
            return seen.insert(browser.bundleID).inserted
        }
        return deduped.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }
}
