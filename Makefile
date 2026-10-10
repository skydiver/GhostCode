PROJECT = Ghostty/macos/Ghostty.xcodeproj
SCHEME  = Ghostty
CONFIG  = Debug
DERIVED = build
APP     = $(DERIVED)/Build/Products/$(CONFIG)/GhostCode.app

# Ghostty core (Zig). Upstream needs Zig 0.16; prefer Homebrew's zig@0.16 over
# whatever `zig` is on PATH. Override with ZIG=/path/to/zig.
ZIG         ?= $(firstword $(wildcard /opt/homebrew/opt/zig@0.16/bin/zig) zig)
CORE_DIR     = Ghostty
XCFRAMEWORK  = $(CORE_DIR)/macos/GhosttyKit.xcframework
# Zig test filter for `make test-core`, e.g. TEST_FILTER=execCommand.
TEST_FILTER ?=

# Builds are signed with the project's settings. ADHOC=1 signs ad hoc instead
# (no team or provisioning profile needed); the project file is not changed.
ADHOC ?=
ifeq ($(ADHOC),1)
SIGN_FLAGS = CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
endif

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED) $(SIGN_FLAGS)

# `make release-silicon`: Apple Silicon only, with debug symbols stripped as
# `xcodebuild archive` does for the GitHub release.
SILICON_FLAGS = ARCHS=arm64 ONLY_ACTIVE_ARCH=NO DEPLOYMENT_POSTPROCESSING=YES STRIP_INSTALLED_PRODUCT=YES

# Upstream Ghostty commit or ref that `make sync` moves Ghostty/ to.
UPSTREAM ?= upstream/main

.DEFAULT_GOAL := help

.PHONY: help core build run launch stop test test-core release release-silicon sync config clean clean-core

help: ## Show this help
	@echo "GhostCode — make targets:"
	@echo "  make core             Build the Ghostty core and GhosttyKit.xcframework (Zig)"
	@echo "  make build            Build the app ($(CONFIG)); builds the core first if missing"
	@echo "  make run              Quit the running app, build, then relaunch"
	@echo "  make launch           Relaunch the built app (no build)"
	@echo "  make stop             Quit the running app"
	@echo "  make test             Run the Xcode unit tests (UI tests skipped)"
	@echo "  make test-core        Run the Zig core tests (TEST_FILTER=name to narrow)"
	@echo "  make release          Build the core (ReleaseFast) and the app (Release, universal)"
	@echo "  make release-silicon  Stripped Release build, Apple Silicon only"
	@echo "  make sync             Sync Ghostty/ to upstream as one commit (UPSTREAM=$(UPSTREAM))"
	@echo "  make config           Open the GhostCode config file"
	@echo "  make clean            Remove app build artifacts"
	@echo "  make clean-core       Remove Zig build artifacts and the xcframework"
	@echo ""
	@echo "Options: ADHOC=1 (ad-hoc signing), CONFIG=Release, ZIG=/path/to/zig"

core: ## Build the Ghostty core and GhosttyKit.xcframework (Zig)
	cd $(CORE_DIR) && $(ZIG) build -Demit-macos-app=false

$(XCFRAMEWORK):
	@echo "→ GhosttyKit.xcframework missing, building the core first…"
	@$(MAKE) core

build: | $(XCFRAMEWORK) ## Build the app (Debug)
	$(XCODEBUILD) -configuration $(CONFIG) build

run: stop build launch ## Quit the running app, build, then relaunch

launch: stop ## Relaunch the built app without rebuilding
	@sleep 0.4
	open "$(APP)"

stop: ## Quit the running app
	-@pkill -f GhostCode.app 2>/dev/null || true

test: | $(XCFRAMEWORK) ## Run the Xcode unit tests (UI tests skipped)
	$(XCODEBUILD) -configuration Debug -skip-testing GhosttyUITests test

test-core: ## Run the Zig core tests
	cd $(CORE_DIR) && $(ZIG) build test $(if $(TEST_FILTER),-Dtest-filter=$(TEST_FILTER))

release: ## Build the core (ReleaseFast) and the app (Release, universal)
	cd $(CORE_DIR) && $(ZIG) build -Demit-macos-app=false -Doptimize=ReleaseFast
	$(XCODEBUILD) -configuration Release build
	@echo "\n✅ Release build complete:"
	@du -sh "$(DERIVED)/Build/Products/Release/GhostCode.app"

release-silicon: ## Build a stripped, Apple Silicon-only Release app
	cd $(CORE_DIR) && $(ZIG) build -Demit-macos-app=false -Doptimize=ReleaseFast -Dxcframework-target=native
	$(XCODEBUILD) -configuration Release $(SILICON_FLAGS) build
	@echo "\n✅ Apple Silicon release build complete:"
	@du -sh "$(DERIVED)/Build/Products/Release/GhostCode.app"

sync: ## Sync Ghostty/ to upstream as one commit
	git fetch upstream
	GhostCode/scripts/sync-upstream.sh $(UPSTREAM)

config: ## Open the GhostCode config file (created empty if missing, as the app does)
	@mkdir -p ~/.config/ghostcode && touch ~/.config/ghostcode/config
	open ~/.config/ghostcode/config

clean: ## Remove app build artifacts
	rm -rf $(DERIVED)

clean-core: ## Remove Zig build artifacts and the xcframework
	rm -rf $(CORE_DIR)/zig-out $(CORE_DIR)/.zig-cache $(XCFRAMEWORK)
