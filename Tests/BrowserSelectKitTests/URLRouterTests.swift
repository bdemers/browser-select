import XCTest

@testable import BrowserSelectKit

final class URLRouterTests: XCTestCase {

    // MARK: - Acceptance

    /// Both schemes are accepted and produce the expected scheme/host. The https case
    /// also carries a path, query, and fragment to confirm those survive sanitization.
    func testHTTPAndHTTPSAccepted() {
        let http = URLRouter.sanitize("http://example.com")
        XCTAssertEqual(http?.scheme, "http")
        XCTAssertEqual(http?.host, "example.com")

        let https = URLRouter.sanitize("https://example.com/path?q=1#frag")
        XCTAssertEqual(https?.scheme, "https")
        XCTAssertEqual(https?.host, "example.com")
        XCTAssertEqual(https?.path, "/path")
        XCTAssertEqual(https?.query, "q=1")
        XCTAssertEqual(https?.fragment, "frag")
    }

    // MARK: - Rejection of malformed / disallowed input

    func testMalformedAndDisallowedURLsRejected() {
        let bad = [
            "",  // empty
            "   ",  // whitespace only
            "not a url",  // no scheme/host
            "file:///etc/passwd",  // disallowed scheme
            "javascript:alert(1)",  // disallowed scheme
            "ftp://example.com",  // disallowed scheme
            "http://",  // no host
            "https://",  // no host
        ]
        for input in bad {
            XCTAssertNil(URLRouter.sanitize(input), "Expected nil for input: \(input)")
        }
    }

    // MARK: - Normalization round-trip

    /// Scheme and host are lowercased; path, query, and fragment survive unchanged.
    func testNormalizationRoundTrip() {
        let result = URLRouter.sanitize("HTTPS://Example.COM/Path/To?Query=Value#Frag")
        XCTAssertEqual(result?.scheme, "https")
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.path, "/Path/To")
        XCTAssertEqual(result?.query, "Query=Value")
        XCTAssertEqual(result?.fragment, "Frag")
        XCTAssertEqual(
            result?.absoluteString,
            "https://example.com/Path/To?Query=Value#Frag")
    }

    /// Leading/trailing whitespace is trimmed before parsing.
    func testWhitespaceTrimmed() {
        let result = URLRouter.sanitize("  http://example.com/x  ")
        XCTAssertEqual(result?.absoluteString, "http://example.com/x")
    }

    // MARK: - Port preservation

    /// An explicit port must be preserved through sanitization (full round-trip).
    func testPortPreserved() {
        let result = URLRouter.sanitize("https://example.com:8080/path?q=v")
        XCTAssertEqual(result?.port, 8080)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.absoluteString, "https://example.com:8080/path?q=v")
    }

    // MARK: - Userinfo stripping (security decision)

    /// Credentials embedded as `user:pass@host` are STRIPPED before forwarding to a
    /// browser: they are a credential-leak hazard and rarely intended for navigation.
    /// The rest of the URL (host/path/query/fragment) is preserved.
    func testUserInfoStripped() {
        let result = URLRouter.sanitize("https://user:pass@example.com/x?q=v#f")
        XCTAssertNil(result?.user)
        XCTAssertNil(result?.password)
        XCTAssertEqual(result?.host, "example.com")
        XCTAssertEqual(result?.absoluteString, "https://example.com/x?q=v#f")
        XCTAssertFalse(result?.absoluteString.contains("user") ?? true)
        XCTAssertFalse(result?.absoluteString.contains("pass") ?? true)
    }

    // MARK: - Host boundary behavior (pinned, not necessarily "ideal")

    /// These pin the router's CURRENT host handling. The router is intentionally
    /// permissive about host shape — final hostname validation is the chosen browser's
    /// job. We only require a non-empty host and a valid http/https scheme.
    func testHostBoundaryBehaviorIsPinned() {
        // Single-label host (no dots) is accepted (e.g. intranet hostnames).
        XCTAssertEqual(URLRouter.sanitize("https://example")?.host, "example")

        // IPv6 literal is accepted; brackets are preserved in the serialized URL even
        // though URL.host reports the unbracketed form.
        let ipv6 = URLRouter.sanitize("https://[::1]:8080/x")
        XCTAssertEqual(ipv6?.host, "::1")
        XCTAssertEqual(ipv6?.port, 8080)
        XCTAssertEqual(ipv6?.absoluteString, "https://[::1]:8080/x")

        // Leading/trailing-hyphen hosts are technically invalid per RFC but are accepted
        // here (passed through to the browser to reject/resolve).
        XCTAssertEqual(URLRouter.sanitize("https://-example.com")?.host, "-example.com")
        XCTAssertEqual(URLRouter.sanitize("https://example-.com")?.host, "example-.com")
    }
}
