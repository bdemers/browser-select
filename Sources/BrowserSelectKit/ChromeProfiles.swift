import Foundation

/// A single Chrome profile, as read from Chrome's `Local State` file.
///
/// Pure value type (no AppKit / no file I/O) so the parsing logic is unit-testable
/// headlessly. The app layer reads the file from disk and hands the bytes to
/// `ChromeProfiles.parse(localStateJSON:)`.
public struct ChromeProfile: Equatable, Sendable {
    /// The on-disk profile directory name (e.g. `"Default"`, `"Profile 11"`). This is the
    /// value passed to Chrome's `--profile-directory=` launch argument.
    public let directory: String
    /// The user-facing profile name (e.g. `"Personal"`, `"gradle.com"`).
    public let name: String

    public init(directory: String, name: String) {
        self.directory = directory
        self.name = name
    }
}

/// Parses Google Chrome's `Local State` JSON into the list of configured profiles.
///
/// Chrome stores profile metadata at
/// `~/Library/Application Support/Google/Chrome/Local State` under
/// `profile.info_cache` (a map of directory name → metadata, including `name`), with an
/// optional `profile.profiles_order` array giving the user's preferred ordering.
public enum ChromeProfiles {

    /// Parses `Local State` bytes into an ordered list of profiles.
    ///
    /// - Parameter data: Raw contents of Chrome's `Local State` file.
    /// - Returns: Profiles ordered by `profiles_order` when present, otherwise by display
    ///   name (case-insensitive). Returns an empty array if the data is missing required
    ///   keys or is not valid JSON — callers treat "empty" and "one" as "no profile picker".
    public static func parse(localStateJSON data: Data) -> [ChromeProfile] {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let profile = root["profile"] as? [String: Any],
            let cache = profile["info_cache"] as? [String: Any]
        else {
            return []
        }

        var profiles: [ChromeProfile] = []
        for (directory, rawInfo) in cache {
            let info = rawInfo as? [String: Any]
            let name = (info?["name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? directory
            profiles.append(ChromeProfile(directory: directory, name: name))
        }

        if let order = profile["profiles_order"] as? [String], !order.isEmpty {
            // Stable order using Chrome's own `profiles_order`; anything not listed sorts
            // last, then alphabetically as a tie-break.
            let rank = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            profiles.sort { lhs, rhs in
                let lr = rank[lhs.directory] ?? Int.max
                let rr = rank[rhs.directory] ?? Int.max
                if lr != rr { return lr < rr }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } else {
            profiles.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        return profiles
    }
}
