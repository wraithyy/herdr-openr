# herdr-openr

Jump to what your agent just did.

Your AI agent mentions files constantly — stack traces, edited configs, new
tests, PR links. Getting to them means the little dance: select, copy, `cd`,
paste, fix the path, add the line number. `openr` replaces that with one
keypress: a fuzzy picker over every file and URL the pane just mentioned.
URLs open in your browser; files open in your editor, at the right line.

```
╭─ open ▸ ────────────────────────────────┬──────────────────────────────╮
│ enter open · ctrl-f reveal · ctrl-y copy│  70 │ [[keys.command]]       │
│                                         │  71 │ key = "prefix+o"       │
│ > dot_config/herdr/config.toml:71       │  72 │ type = "plugin_action" │
│   src/ui/keybind_help.rs                │  73 │ command = "openr.pick" │
│   bin/pane-menu                         │     │                        │
│   ~/Development/herdr-openr/            │     │                        │
│   https://herdr.dev/docs/plugins/       │     │                        │
╰─────────────────────────────────────────┴──────────────────────────────╯
```

## The transcript trick

For **Claude Code panes**, openr never scrapes the screen. herdr knows each
agent pane's session; openr resolves it and reads Claude's own transcript
(`~/.claude/projects/<project>/<session>.jsonl`) directly:

| | screen scraping | transcript |
|---|---|---|
| coverage | what happens to be visible | the whole session |
| paths | regex guesses | exact `file_path` from every Edit/Write/Read tool call |
| false positives | version numbers, IPs, prose | none from tool calls |
| side effects | herdr history reads visibly scroll the pane | file on disk, nothing moves |

A file Claude edited twenty turns ago — long scrolled away, never fully
printed — is one keypress away.

For every other pane, openr scans the **visible viewport**: URLs plus path
tokens, kept only when the file actually exists relative to the pane's cwd,
so the list stays short and real. Directories show a trailing `/`.

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

Focus any pane, hit `prefix+o`. Defaults work out of the box — files open
in `nvim` in a new herdr tab. VS Code and friends: see
[Configure](#configure).

### Requirements

| tool | why | required |
|---|---|---|
| [herdr](https://herdr.dev) ≥ 0.7.0 | the multiplexer this plugs into | yes |
| `zsh`, [`fzf`](https://github.com/junegunn/fzf), [`jq`](https://jqlang.github.io/jq/) | picker pane, fuzzy UI, API parsing | yes |
| [`bat`](https://github.com/sharkdp/bat) | syntax-highlighted preview with line highlight | no (falls back to `cat`) |

macOS and Linux. Linux opens URLs with `xdg-open` and copies via
`wl-copy` (Wayland) or `xclip` (X11).

## In the picker

| key | action |
|---|---|
| type | fuzzy-filter |
| `enter` | URL → browser · file → editor at the mentioned line |
| `ctrl-f` | file → reveal in Finder (macOS) / open containing dir (Linux) · URL → same as enter |
| `ctrl-y` | copy full path/URL to clipboard, close |
| `esc` / `ctrl-c` | cancel |

The preview pane (right) shows file contents centered on the mentioned
line, `ls -la` for directories, the URL for links.

## Configure

All optional — defaults work as installed.
`~/.config/herdr/plugins/config/openr/openr.conf` (shell syntax):

```sh
# what to run on selection; {file} {line} {url} are replaced.
# Use bare {file}/{url} — values are shell-escaped before substitution.
file_cmd='nvim +{line} {file}'

# "tab"      = run file_cmd in a new herdr tab (terminal editors)
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

# non-agent panes: which pane source to scan and how far.
# visible (default) has no side effects; recent/recent-unwrapped read
# scrollback history but herdr visibly scrolls the pane while reading it.
scan_source="visible"
scan_lines=400

# agent panes: how many transcript JSONL lines back to scan
transcript_lines=1000
```

Popup size: set `OPENR_WIDTH` / `OPENR_HEIGHT` (defaults `75%` / `60%`),
e.g. via `--env` on the keybind or in the environment herdr starts from.

## How it works

`openr.pick` runs on the herdr server, before any UI appears:

1. resolve the focused pane from the plugin context
2. gather candidate text — the Claude session transcript when the pane is
   a Claude agent, the visible viewport otherwise
3. extract URLs and path tokens, drop paths that don't exist, dedupe by
   resolved path (newest mention first)
4. open the popup — the picker pane just runs `fzf` over the finished
   list, so it appears instantly

Files open via `herdr pane run` in a fresh tab (nothing is typed into a
shell prompt, so there's no race with slow-starting shells), GUI editors
and URLs spawn detached. Candidates are shell-escaped before they touch
any command template — pane and transcript text is untrusted input.

## Troubleshooting

- **Key does nothing** — check `herdr server reload-config` ran without
  errors and `fzf`/`jq` are on PATH. Most failures show an "openr" toast.
- **"popup already open" / nothing appears** — herdr refuses popups while
  another popup/overlay or modal view is active; close it first.
- **A file is missing from the list** — paths containing spaces are not
  detected (known limit), and non-agent panes only see what's currently
  visible in the viewport.
- **What did it actually run?** —
  `~/.config/herdr/plugins/config/openr/last.log` holds the last dispatched
  command, `last-source.log` the last scanned pane + source.

## License

[MIT](LICENSE)
