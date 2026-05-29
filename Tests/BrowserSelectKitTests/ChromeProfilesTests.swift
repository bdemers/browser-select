import XCTest
@testable import BrowserSelectKit

final class ChromeProfilesTests: XCTestCase {

    private func json(_ s: String) -> Data { Data(s.utf8) }

    /// A realistic multi-profile Local State parses into the expected profiles, ordered by
    /// the browser's own `profiles_order`.
    func testParsesMultipleProfilesInDeclaredOrder() {
        let data = json("""
        {
          "profile": {
            "info_cache": {
              "Profile 1": { "name": "Personal" },
              "Default":   { "name": "Work" },
              "Profile 3": { "name": "Testing" }
            },
            "profiles_order": ["Default", "Profile 1", "Profile 3"]
          }
        }
        """)

        let profiles = ChromeProfiles.parse(localStateJSON: data)

        XCTAssertEqual(profiles, [
            ChromeProfile(directory: "Default", name: "Work"),
            ChromeProfile(directory: "Profile 1", name: "Personal"),
            ChromeProfile(directory: "Profile 3", name: "Testing"),
        ])
    }

    /// Without `profiles_order`, profiles sort case-insensitively by display name.
    func testSortsByNameWhenNoOrderPresent() {
        let data = json("""
        {
          "profile": {
            "info_cache": {
              "Profile 1": { "name": "zeta" },
              "Default":   { "name": "Alpha" }
            }
          }
        }
        """)

        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: data).map(\.name), ["Alpha", "zeta"])
    }

    /// A single profile is returned as-is (the app layer decides not to show a picker for it).
    func testSingleProfile() {
        let data = json("""
        { "profile": { "info_cache": { "Profile 11": { "name": "gradle.com" } } } }
        """)

        XCTAssertEqual(ChromeProfiles.parse(localStateJSON: data),
                       [ChromeProfile(directory: "Profile 11", name: "gradle.com")])
    }

    /// A profile whose `name` is missing or empty falls back to its directory name.
    func testMissingNameFallsBackToDirectory() {
        let data = json("""
        { "profile": { "info_cache": { "Profile 2": { "name": "" }, "Profile 3": {} } } }
        """)

        let byDir = Dictionary(uniqueKeysWithValues:
            ChromeProfiles.parse(localStateJSON: data).map { ($0.directory, $0.name) })
        XCTAssertEqual(byDir["Profile 2"], "Profile 2")
        XCTAssertEqual(byDir["Profile 3"], "Profile 3")
    }

    /// Malformed / unrelated JSON yields an empty list rather than throwing.
    func testMalformedOrMissingKeysYieldEmpty() {
        XCTAssertTrue(ChromeProfiles.parse(localStateJSON: json("not json")).isEmpty)
        XCTAssertTrue(ChromeProfiles.parse(localStateJSON: json("{}")).isEmpty)
        XCTAssertTrue(ChromeProfiles.parse(localStateJSON: json(#"{"profile":{}}"#)).isEmpty)
    }
}
