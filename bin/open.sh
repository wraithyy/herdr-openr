#!/usr/bin/env bash
# Action `openr.pick`: runs on the herdr server (no TTY). Reads the origin
# pane, extracts candidate URLs/paths, filters paths to existing files, and
# hands the finished list to the picker popup via a temp file — the popup
# only runs fzf, so it opens instantly.
set -uo pipefail

# mode: auto (default) = transcript for claude panes, pane read otherwise;
# visible = always read the pane viewport; transcript = claude transcript only
mode="${1:-auto}"

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

fail() {
  "$herdr_bin" notification show "openr" --body "$1" 2>/dev/null
  exit 1
}
command -v jq >/dev/null 2>&1 || fail "jq is not installed"

pane_id=""; cwd=""
if [ -n "$ctx" ]; then
  pane_id="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty')"
  cwd="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')"
fi
[ -n "$pane_id" ] || fail "could not resolve the focused pane"
[ -d "$cwd" ] || cwd="$HOME"

# user config (scan_source/scan_lines here; file_cmd/url_cmd read by the picker)
# visible by default: history sources (recent/recent-unwrapped) visibly
# scroll the origin pane while the server reads it
scan_source="visible"
scan_lines=400
transcript_lines=1000
conf="$HOME/.config/herdr/plugins/config/openr/openr.conf"
# shellcheck disable=SC1090
[ -r "$conf" ] && . "$conf"

# Claude panes: read the session transcript instead of scraping the screen —
# full history, exact tool-call paths, and zero pane reads (nothing scrolls).
# The transcript text feeds the same extraction pipeline as pane content.
transcript=""
if [ "$mode" != "visible" ]; then
pane_json="$("$herdr_bin" pane get "$pane_id" 2>/dev/null)"
if [ "$(printf '%s' "$pane_json" | jq -r '.result.pane.agent // empty')" = "claude" ]; then
  sid="$(printf '%s' "$pane_json" | jq -r '.result.pane.agent_session.value // empty')"
  pane_cwd="$(printf '%s' "$pane_json" | jq -r '.result.pane.cwd // empty')"
  if [ -n "$sid" ] && [ -n "$pane_cwd" ]; then
    slug="$(printf '%s' "$pane_cwd" | sed 's/[\/.]/-/g')"
    t="$HOME/.claude/projects/$slug/$sid.jsonl"
    [ -r "$t" ] && transcript="$t"
  fi
fi
fi

if [ "$mode" = "transcript" ] && [ -z "$transcript" ]; then
  fail "no Claude transcript for this pane"
fi
[ "$mode" = "visible" ] && scan_source="visible"

printf '%s src=%s pane=%s cwd=%s\n' "$(date '+%H:%M:%S')" \
  "${transcript:-pane-$scan_source}" "$pane_id" "$cwd" \
  > "$HOME/.config/herdr/plugins/config/openr/last-source.log" 2>/dev/null

scan_text() {
  if [ -n "$transcript" ]; then
    # tool_use file paths as their own lines + message text (URLs, mentions)
    tail -n "$transcript_lines" "$transcript" | jq -Rr 'fromjson?
      | .message.content[]?
      | if .type == "tool_use" then (.input.file_path // .input.notebook_path // empty)
        elif .type == "text" then .text
        else empty end' 2>/dev/null
  else
    "$herdr_bin" pane read "$pane_id" --source "$scan_source" --lines "$scan_lines" 2>/dev/null
  fi
}

# URLs, then path-looking tokens (with a slash, or ending .ext[:line]).
# Dedupe, newest mention first.
candidates="$(
  scan_text | awk '
    {
      # $ and backtick excluded: extracted text feeds command templates,
      # keep shell-expansion characters out of candidates entirely
      while (match($0, /https?:\/\/[^[:space:]"'"'"'`$()\]>]+/)) {
        print "url\t" substr($0, RSTART, RLENGTH)
        $0 = substr($0, RSTART + RLENGTH)
      }
    }
    {
      line = $0
      while (match(line, /(\/[A-Za-z0-9_.@~-][A-Za-z0-9_.@~\/-]*|[A-Za-z0-9_.@~-]+\/[A-Za-z0-9_.@~\/-]+|[A-Za-z0-9_@~][A-Za-z0-9_.@~\/-]*\.[A-Za-z0-9][A-Za-z0-9]*)(:[0-9]+)?/)) {
        tok = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
        print "file\t" tok
      }
    }
  ' | awk '!seen[$0]++' | if command -v tac >/dev/null 2>&1; then tac; else tail -r; fi
)"

# keep files that actually exist (relative to the pane cwd); no subshell forks
list="$(mktemp "${TMPDIR:-/tmp}/openr.XXXXXX")"
while IFS=$'\t' read -r kind tok; do
  if [ "$kind" = "url" ]; then
    printf 'url\t%s\t%s\n' "$tok" "$tok"
    continue
  fi
  p="${tok%%:[0-9]*}"
  p="${p/#\~/$HOME}"
  case "$p" in
    /dev/*) continue ;;
    /*) abs="$p" ;;
    *) abs="$cwd/$p" ;;
  esac
  if [ -d "$abs" ]; then
    printf 'file\t%s/\t%s\n' "${tok%/}" "$abs"
  elif [ -e "$abs" ]; then
    printf 'file\t%s\t%s\n' "$tok" "$abs"
  fi
done <<< "$candidates" | awk -F'\t' '!seen[$3]++ { print $1 "\t" $2 }' > "$list"

if [ ! -s "$list" ]; then
  rm -f "$list"
  "$herdr_bin" notification show "openr" --body "nothing openable in pane output" 2>/dev/null
  exit 0
fi

if ! "$herdr_bin" plugin pane open \
  --plugin openr \
  --entrypoint picker \
  --placement popup \
  --width "${OPENR_WIDTH:-75%}" \
  --height "${OPENR_HEIGHT:-60%}" \
  --env "OPENR_LIST=$list" \
  --env "OPENR_PANE=$pane_id" \
  --env "OPENR_CWD=$cwd" \
  --focus; then
  rm -f "$list"
  fail "could not open the picker popup"
fi
