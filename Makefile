# BrowserSelect — build the SPM executable and assemble a runnable .app bundle.
#
# `swift run` is NOT valid for an LSUIElement accessory app (it ignores the Info.plist
# and won't register as a URL handler), so the app must be run from the assembled bundle.

APP_NAME    := BrowserSelect
EXECUTABLE  := BrowserSelectApp
BUILD_DIR   := build
APP_BUNDLE  := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS    := $(APP_BUNDLE)/Contents

# Where `install` places the app. macOS only lists apps in System Settings →
# Default web browser when they live in /Applications (or ~/Applications) and are
# registered there — running from build/ is not enough.
INSTALL_DIR := /Applications
INSTALLED   := $(INSTALL_DIR)/$(APP_NAME).app
LSREGISTER  := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# Deferred (`=`, not `:=`) so the swift tooling that resolves the per-arch bin paths runs
# only inside the recipe that needs it — `make clean` / `make test` must not invoke a build.
RELEASE_BIN = $(shell swift build -c release --show-bin-path)/$(EXECUTABLE)
ARM64_BIN   = $(shell swift build -c release --arch arm64 --show-bin-path)/$(EXECUTABLE)
X86_64_BIN  = $(shell swift build -c release --arch x86_64 --show-bin-path)/$(EXECUTABLE)

.PHONY: all bundle bundle-universal build test install uninstall icon clean

all: bundle

# Compile the kit + app in release configuration (host arch) for a quick local check.
build:
	swift build -c release

# Run the headlessly-testable kit tests.
test:
	swift test --filter BrowserSelectKitTests

# Build a HOST-ARCH release binary, assemble build/BrowserSelect.app from it plus
# AppBundle/Info.plist, then apply an ad-hoc signature so it launches locally.
# This is the default: it builds only for the architecture you're on (no x86_64 SDK
# required) and completes quickly. For a fat arm64+x86_64 bundle, use `bundle-universal`.
bundle:
	@echo "Building host-arch release binary"
	swift build -c release
	@echo "Assembling $(APP_BUNDLE)"
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	cp "$(RELEASE_BIN)" "$(CONTENTS)/MacOS/$(EXECUTABLE)"
	cp AppBundle/Info.plist "$(CONTENTS)/Info.plist"
	cp AppBundle/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	# DEVELOPMENT-ONLY signing: `codesign -s -` is an ad-hoc signature — no tamper-evident
	# Developer ID identity and no Hardened Runtime. For distribution, sign with a Developer
	# ID Application certificate and `--options runtime`, then notarize. (README covers the
	# Gatekeeper/xattr first-launch step for locally-built, ad-hoc-signed bundles.)
	codesign -s - --force "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
	@lipo -info "$(CONTENTS)/MacOS/$(EXECUTABLE)" || true
	@echo "Run with:  open $(APP_BUNDLE)"

# Build a UNIVERSAL (arm64 + x86_64) release binary and assemble the bundle from it.
# REQUIRES the x86_64 platform SDK installed alongside the arm64 toolchain; the cross
# build is significantly SLOWER than the host-arch `bundle` and may stall on machines
# without both SDKs. Use this only when you need a fat binary for distribution to both
# Apple Silicon and Intel Macs.
bundle-universal:
	@echo "Building universal release binary (arm64 + x86_64) — requires x86_64 SDK, may be slow"
	swift build -c release --arch arm64 --arch x86_64
	@echo "Assembling $(APP_BUNDLE)"
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(CONTENTS)/MacOS" "$(CONTENTS)/Resources"
	# --arch builds emit a single fat binary; copy it directly. (lipo -create is a no-op
	# here but documents intent if the build is ever split per-arch.)
	cp "$(ARM64_BIN)" "$(CONTENTS)/MacOS/$(EXECUTABLE)"
	cp AppBundle/Info.plist "$(CONTENTS)/Info.plist"
	cp AppBundle/AppIcon.icns "$(CONTENTS)/Resources/AppIcon.icns"
	# DEVELOPMENT-ONLY signing: see the `bundle` target above — ad-hoc, dev-only.
	codesign -s - --force "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"
	@lipo -info "$(CONTENTS)/MacOS/$(EXECUTABLE)" || true
	@echo "Run with:  open $(APP_BUNDLE)"

# Build the bundle, install it to /Applications, and (re)register it with Launch
# Services so it shows up in System Settings → Desktop & Dock → Default web browser.
# Re-run this after every code change: `make bundle` only refreshes build/, which macOS
# does not surface in the Default-browser picker.
install: bundle
	@echo "Installing to $(INSTALLED)"
	# Unregister any prior copy (e.g. a stale build/ registration) to avoid duplicates.
	-"$(LSREGISTER)" -u "$(CURDIR)/$(APP_BUNDLE)" >/dev/null 2>&1
	-"$(LSREGISTER)" -u "$(INSTALLED)" >/dev/null 2>&1
	rm -rf "$(INSTALLED)"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_DIR)/"
	# Force-register the installed copy so LS indexes it from its final location.
	"$(LSREGISTER)" -f "$(INSTALLED)"
	@echo "Installed and registered $(INSTALLED)"
	@echo "Set it as default in System Settings -> Desktop & Dock -> Default web browser."
	@echo "(If System Settings is open, quit and reopen it so its app list refreshes.)"

# Remove the installed app and its Launch Services registration.
uninstall:
	-"$(LSREGISTER)" -u "$(INSTALLED)" >/dev/null 2>&1
	rm -rf "$(INSTALLED)"
	@echo "Removed $(INSTALLED)"

# Regenerate the app icon (AppBundle/AppIcon.icns) from scripts/make-icon.swift.
# The .icns is committed so a normal `make bundle` doesn't need to regenerate it;
# run this only after changing the icon artwork.
icon:
	swift scripts/make-icon.swift "$(BUILD_DIR)/AppIcon.iconset"
	iconutil -c icns "$(BUILD_DIR)/AppIcon.iconset" -o AppBundle/AppIcon.icns
	@echo "Wrote AppBundle/AppIcon.icns"

clean:
	swift package clean
	rm -rf "$(BUILD_DIR)"
