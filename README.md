<h1>
<p align="center">
  GhostCode
  <br>
  <sub>macOS AI coding terminal manager based on Ghostty</sub>
</p>
</h1>
<p align="center">
  <a href="#about">About</a>
  ·
  <a href="#features">Features</a>
  ·
  <a href="#install">Install</a>
  ·
  <a href="#building">Building</a>
  ·
  <a href="#syncing-with-upstream-ghostty">Upstream</a>
  ·
  <a href="#license-and-attribution">License</a>
</p>

> [!IMPORTANT]
> **GhostCode is an independent, unofficial fork of [Ghostty](https://github.com/ghostty-org/ghostty).**
>
> All terminal emulation is provided by Ghostty's core engine. GhostCode adds a SwiftUI application layer on top for AI coding workflows, and periodically syncs with upstream Ghostty (see [Syncing with Upstream Ghostty](#syncing-with-upstream-ghostty)).
>
> GhostCode is **not affiliated with, endorsed by, or supported by** the Ghostty project or Mitchell Hashimoto. The original Ghostty source code is licensed under the MIT License — Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors.

## About

GhostCode is a macOS-native application that wraps [Ghostty's](https://ghostty.org) terminal engine in a purpose-built interface for AI-assisted coding workflows. It provides a three-panel layout — project sidebar, terminal, and command palette — designed around managing multiple projects where each runs an AI coding assistant.

Rather than being a general-purpose terminal emulator, GhostCode is opinionated: it launches AI CLI tools ([Claude Code](https://docs.anthropic.com/en/docs/claude-code), [Codex](https://github.com/openai/codex), or [OpenCode](https://github.com/opencode-ai/opencode)) inside Ghostty-powered terminals, with project-aware context and quick-access commands alongside them.

GhostCode is **macOS only**, built entirely with SwiftUI and AppKit.

## Install

Download the latest universal binary from the [Releases](https://github.com/skydiver/GhostCode/releases) page.

**The app is signed and notarized by Apple** — you can run it immediately without Gatekeeper warnings.

1. Download `GhostCode-<version>-universal.zip`
2. Unzip and drag `GhostCode.app` to your Applications folder
3. Launch GhostCode

Requires macOS 13.0 or later. Runs natively on both Apple Silicon and Intel Macs.

## Screenshots

|                                                                                                               |                                                                                                             |
| ------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| [![Splash screen](GhostCode/assets/screenshot-splash.png)](GhostCode/assets/screenshot-splash.png)            | [![Project landing page](GhostCode/assets/screenshot-landing.png)](GhostCode/assets/screenshot-landing.png) |
| Splash screen with project list and command palette                                                           | Project landing page with binary picker                                                                     |
| [![Claude Code terminal](GhostCode/assets/screenshot-terminal.png)](GhostCode/assets/screenshot-terminal.png) | [![OpenCode terminal](GhostCode/assets/screenshot-opencode.png)](GhostCode/assets/screenshot-opencode.png)  |
| Active Claude Code session                                                                                    | OpenCode session with command palette                                                                       |

## Features

### Project Management

- Project list with live git status — branch name, dirty state, ahead/behind counts
- Per-project AI binary preference (Claude Code, Codex, or OpenCode)
- Project landing page showing session count and last-used date
- "Open With" context menu integration (VS Code, Tower)

### Terminal Sessions

- Powered by Ghostty's terminal engine (`libghostty`)
- Multiple tabs per project (AI and shell) with standard macOS keyboard shortcuts
- Session resume support for Claude Code (`--continue`)
- Background session indicators (active/inactive/visible state tracking)
- Terminal exit detection with automatic return to landing page

### Command Palette

- Configurable command buttons defined in JSONC
- Flow and list layout modes with section headers
- File watcher — auto-reloads on save, no restart needed
- Tooltip support on command buttons

### Configuration

All configuration lives in `~/.config/ghostcode/`:

| File             | Purpose                                               |
| ---------------- | ----------------------------------------------------- |
| `config`         | Terminal settings, layered on top of Ghostty defaults |
| `projects.jsonc` | Project directory list                                |
| `commands.jsonc` | Command palette buttons and sections                  |

JSONC (JSON with Comments) is supported across all config files. See [customizations.md](GhostCode/docs/customizations.md) for the full command palette format.

## Supported Binaries

| Binary      | Resume Session     | Session Info |
| ----------- | ------------------ | ------------ |
| Claude Code | Yes (`--continue`) | Yes          |
| Codex       | —                  | —            |
| OpenCode    | —                  | —            |

## Repository Layout

```
.
├── Makefile                  Build, test, and sync commands (run `make` for the list)
├── README.md
├── LICENSE
├── .github/workflows/        Release workflow (build, sign, notarize, publish)
├── Ghostty/                  Upstream Ghostty plus the patches GhostCode needs
│   ├── src/                  Ghostty core (Zig)
│   └── macos/                Xcode project and Ghostty's macOS app layer
└── GhostCode/                Everything GhostCode owns
    ├── Sources/              SwiftUI app layer (sidebars, tabs, config, startup screen)
    ├── Tests/                Unit tests for GhostCode
    ├── docs/                 User documentation (see customizations.md)
    ├── assets/               README screenshots
    ├── scripts/              sync-upstream.sh
    └── ExportOptions.plist   Release export settings
```

- `Ghostty/` stays as close to upstream as possible: GhostCode only patches the files it must (app entry points, branding, and a small core change for `hush-login`). This keeps upstream syncs small.
- The Xcode project lives in `Ghostty/macos/` and compiles `GhostCode/Sources` and `GhostCode/Tests` into the same app and test targets, because GhostCode builds directly on Ghostty's macOS app layer.

## Building

For a step-by-step setup — cloning, signing, running, tests, logs, and troubleshooting — see the [Development Guide](GhostCode/docs/development.md).

### Requirements

- macOS with **Xcode 26** (macOS 26 SDK)
- **Zig 0.16** — `brew install zig@0.16`

See Ghostty's [HACKING.md](Ghostty/HACKING.md) for more on the Zig toolchain.

### Make targets

Run `make` with no arguments to list every target.

| Command                | What it does                                                         |
| ---------------------- | -------------------------------------------------------------------- |
| `make build`           | Build the app (Debug). Builds the Ghostty core first if it's missing |
| `make run`             | Quit the running app, build, then relaunch                           |
| `make test`            | Run the Xcode unit tests (UI tests skipped)                          |
| `make test-core`       | Run the Ghostty core (Zig) tests. `TEST_FILTER=name` narrows them    |
| `make core`            | Rebuild the Ghostty core and `GhosttyKit.xcframework`                |
| `make release`         | Build the core (ReleaseFast) and the app (Release, universal)        |
| `make release-silicon` | Stripped Release build for Apple Silicon only                        |
| `make sync`            | Sync `Ghostty/` with upstream (see below)                            |
| `make config`          | Open `~/.config/ghostcode/config`                                    |
| `make clean`           | Remove app build output (`build/`)                                   |
| `make clean-core`      | Remove Zig build output and the xcframework                          |

The app is built to `build/Build/Products/Debug/GhostCode.app`. Builds use the project's signing settings; add `ADHOC=1` to sign ad hoc (no Apple team needed), e.g. `make run ADHOC=1`.

To work in Xcode instead, run `make core` once, then open `Ghostty/macos/Ghostty.xcodeproj` and build the **Ghostty** scheme (it produces `GhostCode.app`).

The bundle identifier is `com.flydev.ghostcode`, so GhostCode can be installed alongside Ghostty without conflict.

## Syncing with Upstream Ghostty

One-time setup:

```sh
git remote add upstream https://github.com/ghostty-org/ghostty.git
```

Then, to bring `Ghostty/` up to date:

```sh
make sync                      # sync to upstream/main
make sync UPSTREAM=<commit>    # or to a specific upstream commit
```

Each sync lands as **one commit** on top of the current branch — no merge commits, no rewritten history. The commit records the upstream commit in a `Ghostty-Upstream:` trailer, which the next sync uses as its base, so only new upstream changes are applied.

Only files GhostCode patched inside `Ghostty/` can conflict. Resolve them, `git add`, then `git cherry-pick --continue`. After a sync, run `make core` and `make test` before pushing.

## License and Attribution

GhostCode is a derivative work of [Ghostty](https://github.com/ghostty-org/ghostty), distributed under the **MIT License**.

The original Ghostty source code and its copyright belong to its authors:

> Copyright (c) 2024 Mitchell Hashimoto, Ghostty contributors

See the [LICENSE](LICENSE) file for the full license text.

GhostCode is **not affiliated with, endorsed by, or supported by** the Ghostty project, Mitchell Hashimoto, or any Ghostty contributors. Any issues with GhostCode should be directed to the [GhostCode repository](https://github.com/skydiver/GhostCode), not to the upstream Ghostty project.

## Acknowledgments

GhostCode exists because of the excellent work by [Mitchell Hashimoto](https://mitchellh.com) and the [Ghostty contributors](https://github.com/ghostty-org/ghostty). Thank you for building a fast, native, and well-architected terminal emulator.
