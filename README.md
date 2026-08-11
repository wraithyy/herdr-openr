# herdr-openr

Jump to what your agent just did.

One keypress pops up a fuzzy picker over the files and URLs your terminal —
or your AI agent — just mentioned: URLs go to your browser, files open in
your editor at the right line.

## Quick start

```bash
herdr plugin install wraithyy/herdr-openr
cat >> ~/.config/herdr/config.toml <<'EOF'

[[keys.command]]
key = "prefix+o"           # prefix = herdr's leader key, ctrl+b by default
type = "plugin_action"
command = "openr.pick"
description = "open file/URL from pane"
EOF
herdr server reload-config
```

Then focus any pane and hit `prefix+o`. Defaults work out of the box —
`nvim` in a new tab; see [Configure](#configure) for VS Code and others.

```
open ▸ pane
┌───────────────────────────────────┬─────────────────────────────┐
│ enter open · ctrl-f reveal ·      │  42 │ [[keys.command]]      │
│ ctrl-y copy · esc cancel          │  43 │ key = "prefix+o"      │
│ > src/ui/keybind_help.rs:71       │  44 │ type = "plugin_a…     │
│   dot_config/herdr/config.toml    │     │                       │
│   https://herdr.dev/docs/…        │     │                       │
└───────────────────────────────────┴─────────────────────────────┘
```

## Why not just scrape the screen?

For **Claude Code panes**, openr doesn't read the screen at all. It resolves
the pane's agent session through the herdr API and reads the session
transcript (`~/.claude/projects/<project>/<session>.jsonl`) directly:

- **exact paths from tool calls** — every file Claude read or edited this
  session, no regex guessing, no false positives
- **full session history** — not just what happens to be on screen
- **zero pane reads** — herdr's history sources visibly scroll the pane
  they're reading; the transcript is a file on disk, nothing moves

For every other pane it falls back to scanning the visible viewport
(URLs + file paths that exist relative to the pane's cwd).

## Requirements

- [herdr](https://herdr.dev) ≥ 0.7.0
- [`fzf`](https://github.com/junegunn/fzf), [`jq`](https://jqlang.github.io/jq/), `zsh`
- [`bat`](https://github.com/sharkdp/bat) (optional — nicer preview with
  line highlighting; falls back to `cat`)

macOS and Linux. Linux additionally uses `xdg-open` and `wl-copy`/`xclip`
(clipboard is a no-op if neither is installed).

## Install for local development

```bash
git clone https://github.com/wraithyy/herdr-openr
herdr plugin link ./herdr-openr
```

The manual keybind in Quick start is needed because herdr does not bind
keys from plugin manifests.

## Use it

Focus the pane you were reading, hit your key. Type to filter, then:

| Key | Action |
|---|---|
| `enter` | URL → browser; file → editor at the mentioned line |
| `ctrl-f` | file: reveal in Finder (macOS) / open containing dir (Linux); URL: same as enter |
| `ctrl-y` | copy full path/URL to clipboard |
| `esc` | cancel |

Directories are listed with a trailing `/`. Files that don't exist (relative
to the pane's cwd) are filtered out, so the list stays short. Known limit:
paths containing spaces are not detected.

**Troubleshooting**: if the key does nothing, check that
`herdr server reload-config` ran without errors and that `fzf` and `jq` are
on PATH; an "openr" toast reports most failures.

## Configure

All optional — the defaults work as installed.
`~/.config/herdr/plugins/config/openr/openr.conf` (shell syntax):

```sh
# what to run on selection; {file} {line} {url} are replaced.
# Use bare {file}/{url} — values are shell-escaped before substitution.
file_cmd='nvim +{line} {file}'
# "tab" = run file_cmd in a new herdr tab (terminal editors)
# "detached" = run it outside herdr (GUI editors)
file_open_in="tab"
# empty = auto (open on macOS, xdg-open on Linux)
url_cmd=""

# editor presets — uncomment one pair:
#   VS Code:  file_open_in="detached"; file_cmd='code --goto {file}:{line}'
#   Zed:      file_open_in="detached"; file_cmd='zed {file}:{line}'
#   Sublime:  file_open_in="detached"; file_cmd='subl {file}:{line}'
#   Helix:    file_open_in="tab";      file_cmd='hx {file}:{line}'

# fzf preview pane on/off
preview="1"

# non-agent panes: which pane source to scan and how far
# (recent/recent-unwrapped read history but visibly scroll the pane)
scan_source="visible"
scan_lines=400
# agent panes: how many transcript JSONL lines back to scan
transcript_lines=1000
```

Popup size can be overridden per-binding with `--env` in the keybind, or by
exporting `OPENR_WIDTH` / `OPENR_HEIGHT` (defaults `75%` / `60%`).

## How it works

`openr.pick` runs on the herdr server: it resolves the focused pane, gathers
candidate text (transcript or visible viewport), extracts and
existence-filters candidates, and only then opens the popup — the picker
pane just runs `fzf` over a prepared list, so it appears instantly. Files
open through `herdr pane run` in a fresh tab (no typing into your shell
prompt), GUI editors and URLs spawn detached.
