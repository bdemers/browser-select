# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html) starting from v0.1.0.

## [Unreleased]

### Added
- Initial release.
- Registers as the macOS system handler for `http`/`https` via `CFBundleURLTypes`
  and an `NSAppleEventManager` `kAEGetURL` handler.
- Lightweight SwiftUI picker of installed browsers (icon + name) with click and
  keyboard (arrows / Return / Escape) selection.
- Forwards the chosen URL to the selected browser via
  `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)`.
- Resident `LSUIElement` accessory app (no Dock icon) with launch-time browser-list
  caching and a pre-warmed hidden picker window for low-latency presentation.
- Background re-enumeration of installed browsers to track installs/uninstalls.
- `BrowserSelectKit` core (URL sanitization, self-exclusion, de-dup, ordering) with
  headless unit tests.
- `make bundle` to assemble an ad-hoc-signed `.app`.

[Unreleased]: https://github.com/bdemers/browser-select/compare/v0.1.0...HEAD
