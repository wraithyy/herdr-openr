#!/usr/bin/env bash
# Action `openr.pick`: runs on the herdr server (no TTY). Captures the origin
# pane's id + cwd and opens the picker popup with them in its environment —
# the popup itself is a different pane, so it can't ask "who invoked me".
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
ctx="${HERDR_PLUGIN_CONTEXT_JSON:-}"

pane_id=""; cwd=""
if [ -n "$ctx" ] && command -v jq >/dev/null 2>&1; then
  pane_id="$(printf '%s' "$ctx" | jq -r '.focused_pane_id // empty')"
  cwd="$(printf '%s' "$ctx" | jq -r '.focused_pane_cwd // .workspace_cwd // empty')"
fi
[ -n "$pane_id" ] || exit 1

exec "$herdr_bin" plugin pane open \
  --plugin openr \
  --entrypoint picker \
  --placement popup \
  --width "70%" \
  --height "50%" \
  --env "OPENR_PANE=$pane_id" \
  --env "OPENR_CWD=$cwd" \
  --focus
