#!/usr/bin/env bash
# Action `openr.install-keybind`: append the default prefix+o binding to
# config.toml (unless openr is already bound or the key is taken) and reload.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"

toast() { "$herdr_bin" notification show "openr" --body "$1" 2>/dev/null; }

if grep -q 'command = "openr.pick"' "$config" 2>/dev/null; then
  toast "already bound — nothing to do"
  exit 0
fi
if grep -q 'key = "prefix+o"' "$config" 2>/dev/null; then
  toast "prefix+o is taken — bind openr.pick manually in config.toml"
  exit 1
fi

cat >> "$config" <<'EOF'

# openr: fuzzy-open recent file paths / URLs from the current pane
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "openr.pick"
description = "open file/URL from pane"
EOF

if "$herdr_bin" server reload-config >/dev/null 2>&1; then
  toast "bound to prefix+o"
else
  toast "keybind written, but reload-config failed — run: herdr server reload-config"
  exit 1
fi
