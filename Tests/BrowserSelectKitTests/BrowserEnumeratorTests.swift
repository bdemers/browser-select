import XCTest

@testable import BrowserSelectKit

final class BrowserEnumeratorTests: XCTestCase {

    private func browser(_ name: String, _ bundleID: String) -> Browser {
        Browser(
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleID: bundleID,
            name: name
        )
    }

    /// Self-exclusion: a synthetic bundle ID injected at init must never appear in output.
    func testSelfIsExcludedByInjectedBundleID() {
        let selfID = "com.example.browserselect.test"
        let enumerator = BrowserEnumerator(excludingBundleID: selfID)

        let result = enumerator.filter(candidates: [
            browser("Safari", "com.apple.Safari"),
            browser("BrowserSelect", selfID),
            browser("Firefox", "org.mozilla.firefox"),
        ])

        XCTAssertFalse(
            result.contains { $0.bundleID == selfID },
            "The injected self bundle ID must be filtered out"
        )
        XCTAssertEqual(result.count, 2)
    }

    /// Duplicate bundle IDs (same app surfaced twice) collapse to a single entry.
    func testDuplicateBundleIDsAreCollapsed() {
        let enumerator = BrowserEnumerator(excludingBundleID: "com.example.self")

        let result = enumerator.filter(candidates: [
            browser("Chrome", "com.google.Chrome"),
            browser("Chrome (copy)", "com.google.Chrome"),
            browser("Safari", "com.apple.Safari"),
        ])

        XCTAssertEqual(
            result.map(\.bundleID).sorted(),
            ["com.apple.Safari", "com.google.Chrome"])
    }

    /// Output is sorted case-insensitively by display name for a stable picker layout.
    func testResultsSortedByNameCaseInsensitive() {
        let enumerator = BrowserEnumerator(excludingBundleID: "com.example.self")

        let result = enumerator.filter(candidates: [
            browser("safari", "com.apple.Safari"),
            browser("Arc", "company.thebrowser.Browser"),
            browser("Firefox", "org.mozilla.firefox"),
        ])

        XCTAssertEqual(result.map(\.name), ["Arc", "Firefox", "safari"])
    }

    /// An empty candidate list yields an empty result without crashing.
    func testEmptyCandidatesYieldEmptyResult() {
        let enumerator = BrowserEnumerator(excludingBundleID: "com.example.self")
        XCTAssertTrue(enumerator.filter(candidates: []).isEmpty)
    }

    /// A single non-excluded candidate passes through unchanged.
    func testSingleBrowserPassesThroughUnchanged() {
        let enumerator = BrowserEnumerator(excludingBundleID: "com.example.self")
        let only = browser("Safari", "com.apple.Safari")
        XCTAssertEqual(enumerator.filter(candidates: [only]), [only])
    }

    /// Known non-browsers (e.g. iTerm) that register as http handlers are dropped by the
    /// default denylist, while real browsers pass through.
    func testDefaultDenylistDropsNonBrowsers() {
        let enumerator = BrowserEnumerator(excludingBundleID: "com.example.self")

        let result = enumerator.filter(candidates: [
            browser("Safari", "com.apple.Safari"),
            browser("iTerm", "com.googlecode.iterm2"),
            browser("Terminal", "com.apple.Terminal"),
            browser("Firefox", "org.mozilla.firefox"),
        ])

        XCTAssertEqual(
            result.map(\.bundleID).sorted(),
            ["com.apple.Safari", "org.mozilla.firefox"])
    }

    /// The denylist is injectable: a custom set filters different bundle IDs.
    func testInjectedDenylistOverridesDefault() {
        let enumerator = BrowserEnumerator(
            excludingBundleID: "com.example.self",
            denylist: ["com.apple.Safari"]
        )

        let result = enumerator.filter(candidates: [
            browser("Safari", "com.apple.Safari"),
            browser("iTerm", "com.googlecode.iterm2"),  // not denylisted under the custom set
        ])

        XCTAssertEqual(result.map(\.bundleID), ["com.googlecode.iterm2"])
    }
}
