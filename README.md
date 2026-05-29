# BrowserSelect

A tiny native macOS app that registers as the system handler for `http`/`https`
URLs, shows a lightweight picker of your installed browsers when you open a link,
and forwards the URL to whichever browser you choose.

Useful when you want per-link control over which browser opens — work vs. personal,
Chromium vs. WebKit, a profile-specific browser, etc.

## Requirements

- macOS 12 (Monterey) or later
- Apple Silicon or Intel — `make bundle` produces a binary for your **host
  architecture**. To produce a **universal** (arm64 + x86_64) bundle that runs natively
  on both, use `make bundle-universal` (requires both platform SDKs installed; the cross
  build is slower).
- Xcode command line tools (`swift`, `codesign`, `plutil`, `make`)

## Build

```sh
# Run the headlessly-testable core logic tests
swift test

# Build the host-arch release binary and assemble build/BrowserSelect.app (ad-hoc signed)
make bundle

# Build, install to /Applications, and register with Launch Services in one step.
# This is what makes the app eligible to be the default browser (see below).
make install

# Optional: build a universal (arm64 + x86_64) bundle instead.
# Requires both platform SDKs installed; the cross build is slower.
make bundle-universal

# Remove the installed app and its Launch Services registration.
make uninstall
```

`make bundle` produces `build/BrowserSelect.app` containing a binary for your **host
architecture** (the machine you build on). For a fat binary that runs natively on both
Apple Silicon and Intel, run `make bundle-universal` instead — it requires the x86_64
platform SDK alongside the arm64 toolchain and takes noticeably longer.

Note that `swift run` will **not**
work for this app: it is an `LSUIElement` accessory app that must be launched from the
assembled bundle so macOS reads its `Info.plist` and registers it as a URL handler.

## Set as Default Browser

1. Run `make install`. This builds the bundle, copies it to `/Applications/BrowserSelect.app`,
   and registers it with Launch Services. **This step matters:** macOS only lists an app in
   the Default-web-browser picker when it lives in `/Applications` (or `~/Applications`) and
   is registered there — an app left in `build/` will not appear.
2. Open **System Settings → Desktop & Dock → Default web browser** and choose
   **BrowserSelect** from the dropdown.
   (On macOS 12 the setting lives in **System Preferences → General → Default web browser**.)
   If System Settings was already open, quit and reopen it so its app list refreshes.

From then on, clicking a link in any app routes through BrowserSelect's picker.

> **After every rebuild, re-run `make install`.** `make bundle` only refreshes `build/`,
> which macOS does not surface in the Default-browser picker; `make install` re-syncs the
> `/Applications` copy and its registration.

## Gatekeeper / First Launch

The bundle is **ad-hoc signed** (`codesign -s -`), not signed with a Developer ID and
not notarized.

**If you built it locally** (`make bundle`), there is **nothing to do** — locally built
apps are not quarantined, so `open build/BrowserSelect.app` just works. (Running
`xattr -d com.apple.quarantine ...` on a local build prints
`No such xattr: com.apple.quarantine`, which is harmless — there was no flag to remove.)

**If you downloaded a prebuilt `BrowserSelect.app`** (e.g. a GitHub release zip), macOS
quarantines it and Gatekeeper blocks the first launch ("cannot be opened because the
developer cannot be verified"). Remove the quarantine attribute the OS added:

```sh
xattr -dr com.apple.quarantine /path/to/BrowserSelect.app
```

Why: ad-hoc signatures carry no notarization ticket, so Gatekeeper quarantines *downloaded*
copies on first launch. Stripping the quarantine flag tells the OS you trust this binary.
(Alternatively, right-click the app → Open → confirm the dialog once.)

## Architecture / How it works

- **Resident accessory process.** `LSUIElement = YES` means no Dock icon and no menu
  bar. The process stays alive in the background after launch, so only the **first**
  click after a reboot pays a cold-start cost; every link after that hits a warm process.
- **URL reception.** The app registers an `NSAppleEventManager` handler for
  `kInternetEventClass` / `kAEGetURL` in `applicationDidFinishLaunching`. The
  `CFBundleURLTypes` entry in `Info.plist` (claiming `http` and `https`) is what makes
  Launch Services deliver those URL-open events to this app.
- **~300 ms picker budget.** The browser list is enumerated and cached **at launch**
  (before the URL handler can fire), and the picker window is **created hidden at launch**
  (pre-warmed). When a URL arrives, the hot path only validates the URL, sets the pending
  URL, and reveals the already-built window — no enumeration or view construction on the
  critical path. A background timer re-enumerates every 30 s to catch browser
  installs/uninstalls.
- **Browser enumeration.** Uses `NSWorkspace.urlsForApplications(toOpen:)` (macOS 12+)
  against a representative `http://example.com` — deliberately **not** the deprecated
  `LSCopyApplicationURLsForURL`.
- **Injected self-exclusion ID.** The core `BrowserEnumerator` excludes this app from its
  own results so it never offers to open URLs in itself (an infinite loop). The excluded
  bundle ID is **injected** via `BrowserEnumerator(excludingBundleID:)` rather than read
  from `Bundle.main`, which keeps the exclusion logic unit-testable headlessly. The app's
  call site passes `Bundle.main.bundleIdentifier`.
- **Launching.** The chosen URL is opened via
  `NSWorkspace.open(_:withApplicationAt:configuration:completionHandler:)` so launch
  failures can be reported asynchronously.

## Manual Verification

Core logic (URL sanitization, self-exclusion, de-dup, ordering) is covered by `swift test`.
The live UI and system-launch paths require a GUI session:

1. `make bundle` (a locally built bundle is not quarantined — no `xattr` step needed).
2. `open build/BrowserSelect.app` — confirm **no Dock icon appears** and **no window shows**.
3. Trigger a URL event without changing your default browser:
   ```sh
   osascript -e 'tell application id "com.bdemers.browserselect" to open location "https://example.com"'
   ```
   The picker should appear within a fraction of a second listing your installed browsers
   (BrowserSelect itself absent).
4. Click a browser, or use Left/Right arrows + Return to choose; the URL should open there.
   Press **Escape** (or click away) to dismiss without opening.
5. To exercise it as the real default browser, follow **Set as Default Browser** above and
   click a link in any app.

### Confirming the <300 ms picker budget

The <300 ms target is a **design goal** and must be confirmed on your own machine — it
cannot be asserted in a headless test. The app instruments the receive→present hot path
and emits the elapsed time to the unified log. With the app running, trigger an event and
read the measurement back:

```sh
# In one terminal, stream the app's routing log:
log stream --predicate 'subsystem == "com.bdemers.browserselect" && category == "routing"' --info

# In another, fire a URL event:
osascript -e 'tell application id "com.bdemers.browserselect" to open location "https://example.com"'
```

The stream prints a line like `Picker presented in 14.2 ms for scheme https`. Note this
measures the **warm** path (process already resident, which is the steady state for an
`LSUIElement` app). The first event after a reboot pays a one-time cold start; trigger a
throwaway URL once after login if you want every subsequent click warm.

If you prefer not to use the log, you can eyeball it: `time osascript -e '...'` brackets the
round trip including AppleScript overhead, which is a loose upper bound.

## Contributing

The project is two SPM targets:

- `BrowserSelectKit` — pure Swift core (no AppKit): `Browser`, `BrowserEnumerator`,
  `URLRouter`. **This is an internal test seam, not a stable public API** — it exists so
  the routing and selection logic can be tested without a GUI session. Treat its surface
  as subject to change.
- `BrowserSelectApp` — the AppKit/SwiftUI app: AppDelegate, picker window/view, and the
  Launch Services discovery glue.

Run `swift test` before sending changes. UI changes need the manual verification recipe
above since they can't be exercised headlessly.
