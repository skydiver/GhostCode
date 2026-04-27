# GhostCode Command Palette Configuration

The right-side command palette is configured via `~/.config/ghostcode/commands.jsonc`. The file is JSONC (JSON with `//` and `/* */` comments). Changes are picked up automatically on save — no restart needed.

If the file doesn't exist, GhostCode creates a starter template the first time the app runs.

---

## File structure

```jsonc
{
  "sections": [
    {
      "name": "...",
      "layout": "flow",
      "items": [{ "label": "...", "text": "..." }],
    },
  ],
}
```

A config has one or more **sections**, displayed top-to-bottom in the sidebar. Each section contains one or more **items** (clickable buttons or tiles).

---

## Section properties

| Field    | Type   | Required | Default | Description                                |
| -------- | ------ | -------- | ------- | ------------------------------------------ |
| `name`   | string | yes      | —       | Section heading shown in the palette       |
| `layout` | string | no       | `flow`  | One of `flow`, `list`, `tiles` (see below) |
| `items`  | array  | yes      | —       | Buttons in this section                    |

### Layout types

| Layout  | Appearance                            | Best for                                           |
| ------- | ------------------------------------- | -------------------------------------------------- |
| `flow`  | Compact, wrapping chips               | Short labels — slash commands, single-word actions |
| `list`  | Full-width stacked rows               | Longer labels, prompts with secondary text         |
| `tiles` | 2-column grid of 56pt-tall rectangles | App launchers, prominent actions                   |

---

## Item properties

| Field          | Type     | Required    | Default          | Description                                                                                                                       |
| -------------- | -------- | ----------- | ---------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `label`        | string   | yes         | —                | Button text shown in the palette                                                                                                  |
| `text`         | string   | conditional | —                | Text sent to the active terminal when clicked                                                                                     |
| `executable`   | string   | conditional | —                | Absolute path to a binary. Default argv is `[<project_path>]`; override with `arguments`.                                         |
| `arguments`    | string[] | no          | —                | Argv for `executable`. `{{path}}` is replaced with the active project path. See [Arguments](#arguments-and-the-path-placeholder). |
| `tooltip`      | string   | no          | —                | Hover tooltip                                                                                                                     |
| `autoSend`     | bool     | no          | `false`          | Press Enter after sending text. Only meaningful for `text` items.                                                                 |
| `icon`         | string   | no          | —                | SF Symbol name **or** base64 SVG data URI. See [Icons](#icons).                                                                   |
| `iconPosition` | string   | no          | layout-dependent | `top` \| `bottom` \| `left` \| `right`. See [Icon position](#icon-position).                                                      |

### `text` vs `executable` — mutually exclusive

Each item must have **exactly one** of `text` or `executable`:

| Field        | Behavior on click                                                                                               |
| ------------ | --------------------------------------------------------------------------------------------------------------- |
| `text`       | Pastes the text into the active terminal. Presses Enter if `autoSend: true`.                                    |
| `executable` | Spawns the binary as a new process. Argv defaults to `[<project_path>]`; override with `arguments` (see below). |

An item with both fields, or with neither, fails to load — and the entire config file errors out, leaving the palette empty.

`executable` paths must be **absolute** (start with `/`). Relative paths are rejected.

### Arguments and the `{{path}}` placeholder

For executables that need flag-style invocation (e.g. apps that take a `--working-directory=` argument rather than a positional path), use the `arguments` array. Each element is passed as a separate argv entry, and the literal token `{{path}}` is replaced with the absolute project path before the process spawns.

```jsonc
{
  "label": "Ghostty",
  "executable": "/Applications/Ghostty.app/Contents/MacOS/ghostty",
  "arguments": ["--working-directory={{path}}"],
}
```

Behavior rules:

- `arguments` **omitted** → argv is `[<project_path>]` (legacy default — existing entries keep working).
- `arguments` **present** → argv is exactly the supplied array, with `{{path}}` substituted in each element. Nothing is appended automatically.
- `arguments: []` is valid and means "launch with no arguments at all."
- `{{path}}` may appear anywhere in an argv element, including embedded in flag values (`--foo={{path}}/bar`). All occurrences are replaced.
- The process working directory is **always** set to the project path, regardless of `arguments`.
- `arguments` only applies to `executable` items. Pairing it with `text`, or using it on an item that has no `executable`, is a validation error.

---

## Icons

The `icon` field accepts two formats. Detection is by string prefix.

### SF Symbol

```jsonc
{ "label": "Commit", "text": "/commit", "icon": "checkmark.circle" }
```

- Bare SF Symbol name (e.g. `hammer.fill`, `doc.text`, `arrow.triangle.branch`).
- Browse names with macOS's **SF Symbols** app (free, from Apple).
- Invalid names render nothing — no crash, no log.

### Base64 SVG data URI

```jsonc
{
  "label": "VSCode",
  "executable": "/usr/local/bin/code",
  "icon": "data:image/svg+xml;base64,PHN2Zy4uLg==",
}
```

- Format: `data:image/svg+xml;base64,<base64-encoded-svg-bytes>`.
- Renders **monochrome** (template mode): SVG colors and gradients are discarded; the silhouette is tinted to the current foreground color.
- Automatically adapts to light/dark mode (icon uses `.primary` in tiles, `.secondary` in chip/list rows).
- Decoded `NSImage` instances are cached per-string, so the decode cost is paid once.
- Malformed base64 or non-image bytes render nothing — silent fallback.

#### Encoding an SVG to a data URI

```fish
printf "data:image/svg+xml;base64,%s" (base64 -i icon.svg | tr -d '\n') | pbcopy
```

With SVGO minification first (recommended — typically shrinks the icon 30–70%):

```fish
svgo -i icon.svg -o - --multipass | base64 | tr -d '\n' | \
    awk '{print "data:image/svg+xml;base64,"$0}' | pbcopy
```

A reusable fish function:

```fish
function svg2icon --description "Encode SVG to base64 data URI and copy to clipboard"
    if test -z "$argv[1]"
        echo "Usage: svg2icon <file.svg>" >&2
        return 1
    end
    printf "data:image/svg+xml;base64,%s" (base64 -i $argv[1] | tr -d '\n') | pbcopy
    echo "Copied data URI for $argv[1]"
end
```

#### Recommended SVG sources

| Source    | URL               | Notes                                                  |
| --------- | ----------------- | ------------------------------------------------------ |
| Lucide    | lucide.dev        | Already minified, single-path, ideal for template mode |
| Phosphor  | phosphoricons.com | Multiple weights available                             |
| Heroicons | heroicons.com     | Outline and Solid sets                                 |
| Tabler    | tabler.io/icons   | ~3,000 icons, MIT licensed                             |

### Bundle size considerations

A typical Lucide-style monochrome icon is ~200–500 base64 characters. A complex multi-color brand logo can be 2,000–4,000+ — usually wasted bytes since template rendering flattens colors. Stick with single-color, single-path SVGs for the cleanest result.

---

## Icon position

`iconPosition` controls where the icon sits relative to the label. Allowed values and defaults vary by layout:

| Layout  | Allowed values                   | Default | Notes                                                                                     |
| ------- | -------------------------------- | ------- | ----------------------------------------------------------------------------------------- |
| `tiles` | `top`, `bottom`, `left`, `right` | `top`   | All four positions honored                                                                |
| `flow`  | `left`, `right`                  | `left`  | `top` and `bottom` are silently clamped to `left`                                         |
| `list`  | `left`, `right`                  | `left`  | `right` pushes the icon to the trailing edge of the row; `top`/`bottom` clamped to `left` |

The clamping is intentional — chip and list layouts have their own visual rhythm that vertical icon placement would disrupt. Using `top` or `bottom` in those layouts isn't an error, just a no-op.

---

## Full example

```jsonc
{
  "sections": [
    {
      "name": "Slash Commands",
      "items": [
        { "label": "/commit", "text": "/commit", "icon": "checkmark.circle" },
        { "label": "/help", "text": "/help", "icon": "questionmark.circle" },
        { "label": "/clear", "text": "/clear", "icon": "trash" },
      ],
    },
    {
      "name": "Snippets",
      "layout": "list",
      "items": [
        {
          "label": "Fix failing tests",
          "text": "run the tests, find what's failing, and fix it",
          "icon": "hammer",
          "tooltip": "Send a fix-the-tests prompt to the agent",
          "autoSend": true,
        },
        {
          "label": "Explain this project",
          "text": "read the codebase and explain the architecture",
          "icon": "doc.text.magnifyingglass",
          "iconPosition": "right",
        },
      ],
    },
    {
      "name": "Apps",
      "layout": "tiles",
      "items": [
        {
          "label": "VSCode",
          "executable": "/usr/local/bin/code",
          "icon": "data:image/svg+xml;base64,PHN2Zy4uLg==",
          "iconPosition": "top",
        },
        {
          "label": "Tower",
          "executable": "/Applications/Tower.app/Contents/MacOS/Tower",
          "icon": "arrow.triangle.branch",
          "iconPosition": "left",
        },
        {
          "label": "Ghostty",
          "executable": "/Applications/Ghostty.app/Contents/MacOS/ghostty",
          "arguments": ["--working-directory={{path}}"],
          "icon": "terminal",
        },
      ],
    },
  ],
}
```

---

## Reloading and validation

- The file is watched by the app — saves trigger an immediate reload.
- Atomic saves (delete + rename, used by most editors) are handled — the watcher reattaches.
- If the new file has any validation error, the palette goes empty until the file becomes valid again. The previous valid state is **not** preserved across a bad save.

### Common validation errors

| Error                                    | Cause                                                                             |
| ---------------------------------------- | --------------------------------------------------------------------------------- |
| Item has both `text` and `executable`    | Use exactly one                                                                   |
| Item has neither `text` nor `executable` | Use exactly one                                                                   |
| `executable` doesn't start with `/`      | Provide an absolute path                                                          |
| `arguments` set without `executable`     | `arguments` only applies to executable items                                      |
| Malformed JSONC                          | The parser allows comments but no trailing commas; check for missing/extra braces |

For deeper diagnostics, open Console.app and filter on the subsystem `com.flydev.ghostcode`.
