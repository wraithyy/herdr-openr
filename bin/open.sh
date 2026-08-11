#!/usr/bin/env bash
# Action `openr.pick`: runs on the herdr server (no TTY). Reads the origin
# pane, extracts candidate URLs/paths, filters paths to existing files, and
# hands the finished list to the picker popup via a temp file — the popup
# only runs fzf, so it opens instantly.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

pane_id=""; cwd=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  pane_id="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty')"
  cwd="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')"
fi
[ -n "$pane_id" ] || exit 1
[ -d "$cwd" ] || cwd="$HOME"

# user config (scan_source/scan_lines here; file_cmd/url_cmd read by the picker)
# visible by default: history sources (recent/recent-unwrapped) visibly
# scroll the origin pane while the server reads it
scan_source="visible"
scan_lines=400
conf="$HOME/.config/herdr/plugins/config/openr/openr.conf"
# shellcheck disable=SC1090
[ -r "$conf" ] && . "$conf"

# URLs, then path-looking tokens (with a slash, or ending .ext[:line]).
# Dedupe, newest mention first.
candidates="$(
  "$herdr_bin" pane read "$pane_id" --source "$scan_source" --lines "$scan_lines" 2>/dev/null | awk '
    {
      while (match($0, /https?:\/\/[^[:space:]"'"'"')\]>]+/)) {
        print "url\t" substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
    {
      line = $0
      while (match(line, /(\/[A-Za-z0-9_.@~-][A-Za-z0-9_.@~\/-]*|[A-Za-z0-9_.@~-]+\/[A-Za-z0-9_.@~\/-]+|[A-Za-z0-9_@~][A-Za-z0-9_.@~\/-]*\.[A-Za-z0-9]{1,10})(:[0-9]+)?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        print "file\t" tok
      }
    }
  ' | awk '!seen[$0]++' | tail -r
)"

# keep files that actually exist (relative to the pane cwd); no subshell forks
list="$(mktemp "${TMPDIR:-/tmp}/openr.XXXXXX")"
while IFS=$'\t' read -r kind tok; do
  if [ "$kind" = "url" ]; then
    printf 'url\t%s\n' "$tok"
    continue
  fi
  p="${tok%%:[0-9]*}"
  p="${p/#\~/$HOME}"
  case "$p" in /*) abs="$p" ;; *) abs="$cwd/$p" ;; esac
  if [ -d "$abs" ]; then
    printf 'file\t%s/\n' "${tok%/}"
  elif [ -e "$abs" ]; then
    printf 'file\t%s\n' "$tok"
  fi
done <<< "$candidates" | awk -F'\t' '!seen[$2]++' > "$list"

if [ ! -s "$list" ]; then
  rm -f "$list"
  "$herdr_bin" notification show "openr" --body "nothing openable in pane output" 2>/dev/null
  exit 0
fi

# overlay, not popup: fzf's full-screen redraw scroll-glitches in popup panes,
# overlay is the same placement the command-palette plugin uses without issues
exec "$herdr_bin" plugin pane open \
  --plugin openr \
  --entrypoint picker \
  --placement overlay \
  --env "OPENR_LIST=$list" \
  --env "OPENR_PANE=$pane_id" \
  --env "OPENR_CWD=$cwd" \
  --focus
