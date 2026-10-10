# Development Guide

How to clone GhostCode, build it, run it, and test it on your Mac.

## Requirements

| Tool                 | Version  | Install                                                                  |
| -------------------- | -------- | ------------------------------------------------------------------------ |
| macOS                | 15 or 26 | Xcode 26 runs on macOS 15; you don't need macOS 26 to build              |
| Xcode                | 26       | Mac App Store, then `sudo xcode-select --switch /Applications/Xcode.app` |
| Metal Toolchain      | Xcode 26 | `xcodebuild -downloadComponent MetalToolchain`                           |
| Zig                  | 0.16     | `brew install zig@0.16` (the Makefile finds it automatically)            |
| SwiftLint (optional) | any      | `brew install swiftlint`. Builds lint the Swift code when it's installed |

Check your setup:

```sh
xcode-select -p                                   # should point at Xcode 26
xcrun --find metal                                # should print a path
"$(brew --prefix zig@0.16)/bin/zig" version       # should print 0.16.x
```

## Clone

```sh
git clone https://github.com/skydiver/GhostCode.git
cd GhostCode
```

`GhostCode` is the default branch, so the clone checks it out. You only need the `upstream` remote if you sync with upstream Ghostty (see [Syncing](#syncing-with-upstream-ghostty)).

## Build and Run

```sh
make run ADHOC=1
```

This builds the Ghostty core, builds the app, and launches it. The first build compiles the Zig core and downloads its dependencies, so it takes several minutes; later builds only rebuild what changed.

The app is built to `build/Build/Products/Debug/GhostCode.app`.

| Command                        | What it does                                                    |
| ------------------------------ | --------------------------------------------------------------- |
| `make build ADHOC=1`           | Build the app (Debug). Builds the Ghostty core first if missing |
| `make run ADHOC=1`             | Quit the running app, build, then relaunch                      |
| `make launch`                  | Relaunch the last build without rebuilding                      |
| `make stop`                    | Quit the running app                                            |
| `make core`                    | Rebuild the Ghostty core and `GhosttyKit.xcframework`           |
| `make release ADHOC=1`         | Release build of the core (ReleaseFast) and the app (universal) |
| `make release-silicon ADHOC=1` | Smaller, stripped Release build for Apple Silicon only          |

Run `make` with no arguments for the full list.

### Signing: when to use `ADHOC=1`

The Xcode project signs the app automatically with the maintainer's Apple team. If you aren't on that team, add `ADHOC=1` to every build command: the app is then signed ad hoc, which needs no Apple account. Nothing in the project file changes.

Ad-hoc builds run fine on your own Mac. macOS may ask again for permissions it already granted (such as Accessibility for global keybinds) after a rebuild, because the signature changes each time.

### The Debug app and installed releases

Debug builds use the bundle identifier `com.flydev.ghostcode.debug`, so they run alongside an installed release of GhostCode (`com.flydev.ghostcode`) and alongside Ghostty itself.

## Working in Xcode

1. Build the core once: `make core`.
2. Open `Ghostty/macos/Ghostty.xcodeproj`.
3. Select the **Ghostty** scheme (it produces `GhostCode.app`) and press ⌘R.

If you aren't on the maintainer's team, change the signing team to your own in the target's **Signing & Capabilities** tab, but don't commit that change. Building with `make … ADHOC=1` avoids the issue entirely.

GhostCode's own code shows up in the project navigator as the **GhostCode** and **GhostCodeTests** groups. They are synced folders, so files you add under `GhostCode/Sources` or `GhostCode/Tests` are picked up automatically.

## Where the Code Lives

| Path                 | What's there                                                       |
| -------------------- | ------------------------------------------------------------------ |
| `GhostCode/Sources/` | GhostCode's SwiftUI layer: sidebars, tabs, config, startup screen  |
| `GhostCode/Tests/`   | GhostCode's unit tests                                             |
| `Ghostty/macos/`     | Xcode project and Ghostty's macOS app layer (GhostCode patches it) |
| `Ghostty/src/`       | Ghostty core (Zig), compiled into `GhosttyKit.xcframework`         |

Put new GhostCode code under `GhostCode/`. Change files inside `Ghostty/` only when there's no other way: every patch there can conflict when syncing with upstream.

## Tests

```sh
make test ADHOC=1                       # Xcode unit tests (UI tests skipped)
make test-core                          # Ghostty core (Zig) tests
make test-core TEST_FILTER=execCommand  # only Zig tests whose name matches
```

`make test` should report all tests passed, with 1 skipped.

## Configuration While Developing

GhostCode reads its settings from `~/.config/ghostcode/` (`config`, `projects.jsonc`, `commands.jsonc`). `make config` opens the `config` file.

It also loads your Ghostty configuration (`~/.config/ghostty/config`) underneath its own, so Ghostty settings such as fonts, themes, or `macos-icon` apply to GhostCode too. Keep that in mind when something looks different from a clean setup.

## Logs

```sh
# GhostCode's Swift code (Debug build)
log stream --level debug --predicate 'subsystem == "com.flydev.ghostcode.debug"'

# Ghostty core (Zig)
log stream --level debug --predicate 'subsystem == "com.mitchellh.ghostty"'
```

Crash reports are in `~/Library/Logs/DiagnosticReports/` and named `ghostty-<date>.ips`.

## Syncing with Upstream Ghostty

One-time setup:

```sh
git remote add upstream https://github.com/ghostty-org/ghostty.git
```

Then:

```sh
make sync                      # bring Ghostty/ up to upstream/main
make sync UPSTREAM=<commit>    # or to a specific upstream commit
```

Each sync is one commit on top of the current branch. If it stops on conflicts (only files GhostCode patched inside `Ghostty/` can conflict), resolve them, `git add`, then `git cherry-pick --continue`.

After a sync — or after pulling one someone else made — rebuild the core before building the app:

```sh
make core && make test ADHOC=1
```

## Releases and Updates

Releases are built by the GitHub **Release** workflow (Actions → Release → Run workflow, enter the version). It builds a universal app signed with Developer ID, notarizes and staples it, and publishes `GhostCode-<version>-universal.zip` plus a signed `appcast.xml` on the GitHub release.

Installed copies check `https://github.com/skydiver/GhostCode/releases/latest/download/appcast.xml` once a day and ask before installing. Only workflow builds can update: local builds (`make build`, `make release`, `make release-silicon`) leave updates off, and "Check for Updates…" is disabled in them.

- **Signing key:** the Sparkle EdDSA private key is the `SPARKLE_ED_PRIVATE_KEY` repository secret (also in the password manager). Its public key is `SUPublicEDKey` in `Ghostty/macos/Ghostty-Info.plist`. The workflow fails if they don't match.
- **Testing an update feed:** run a release copy with `GHOSTCODE_UPDATE_ENDPOINT=https://…/appcast.xml` to point it at a test appcast.
- **Pulling a bad release:** mark the previous release as Latest on GitHub; new checks stop offering the bad one.
- **Script tests:** `GhostCode/scripts/tests/test-make-appcast.sh` and `test-verify-ed-signature.sh`.
- **If only the appcast upload fails:** the release exists but has no `appcast.xml`, so installed copies see no update (safe). Re-attach it from the workflow run's output with `gh release upload v<version> appcast.xml --clobber -R skydiver/GhostCode`; re-running the workflow would fail at `gh release create`, because the release already exists.

## Troubleshooting

| Problem                                                            | Fix                                                                                                                      |
| ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------ |
| Zig says it needs a different version                              | Install Zig 0.16 (`brew install zig@0.16`), or point the Makefile at it: `make build ZIG=/path/to/zig`                   |
| Build fails with SDK or `metal` errors                             | Check `xcode-select -p` points at Xcode 26, and install the Metal Toolchain (see [Requirements](#requirements))          |
| Signing error: no team, no certificate, or no provisioning profile | Add `ADHOC=1` to the command                                                                                             |
| Linker or "undefined symbol" errors after pulling                  | The core is out of date. Run `make core`, then build again                                                               |
| App crashes at launch                                              | Check the newest `ghostty-*.ips` in `~/Library/Logs/DiagnosticReports/`, and your `~/.config/ghostty/config` (see above) |
| Strange build state                                                | `make clean` (app) or `make clean-core` (core), then build again                                                         |
