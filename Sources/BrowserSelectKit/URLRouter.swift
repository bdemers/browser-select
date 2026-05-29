import Foundation

/// Validates and normalizes incoming URLs before they are handed to a browser.
///
/// The router is intentionally strict: it only accepts `http`/`https` URLs that
/// have a host. This protects against the app being coerced (via a crafted
/// Apple Event or URL scheme registration) into forwarding `file://`, `javascript:`,
/// or otherwise malformed strings to a browser. Pure value logic, no AppKit, so it
/// is fully unit-testable headlessly.
public enum URLRouter {

    /// Schemes this app is willing to forward. Lowercased for case-insensitive matching.
    public static let allowedSchemes: Set<String> = ["http", "https"]

    /// Validates and normalizes a raw URL string received from a URL-open event.
    ///
    /// - Parameter raw: The string delivered by the Apple Event / URL scheme handler.
    /// - Returns: A normalized `URL` whose scheme is lowercased http/https and which
    ///   has a non-empty host, with any `user:password@` userinfo stripped; `nil` if the
    ///   input is malformed or disallowed.
    public static func sanitize(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard var components = URLComponents(string: trimmed) else { return nil }

        guard let scheme = components.scheme?.lowercased(),
              allowedSchemes.contains(scheme) else {
            return nil
        }

        guard let host = components.host, !host.isEmpty else { return nil }

        // Normalize: lowercase scheme and host; the rest of the URL (path, query,
        // fragment, port) is preserved verbatim so it reaches the browser intact.
        components.scheme = scheme
        components.host = host.lowercased()

        // Strip userinfo (`user:pass@host`). This app forwards URLs to a browser the
        // user picks at runtime, and embedding credentials in a top-level navigation URL
        // is both a credential-leak hazard (the chosen browser may log/sync the full URL)
        // and almost never the user's intent for an opened link. Removing it is safer than
        // forwarding secrets to an arbitrary app.
        components.user = nil
        components.password = nil

        return components.url
    }
}
