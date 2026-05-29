import Foundation

/// An installed browser candidate that can receive an http/https URL.
///
/// This is a plain value type with no AppKit dependency so it can be modeled and
/// asserted on in headless unit tests. The app layer decorates instances with an
/// `NSImage` icon separately (see the app target), keeping this type framework-free.
public struct Browser: Equatable, Identifiable, Sendable {
    /// Filesystem location of the application bundle (e.g. `/Applications/Safari.app`).
    public let url: URL
    /// The bundle identifier used both for display de-duplication and self-exclusion.
    public let bundleID: String
    /// Human-readable name shown in the picker (typically the bundle's display name).
    public let name: String

    /// Stable identity for SwiftUI lists; bundle IDs are unique per installed app.
    public var id: String { bundleID }

    public init(url: URL, bundleID: String, name: String) {
        self.url = url
        self.bundleID = bundleID
        self.name = name
    }
}
