#!/usr/bin/env bash
# Action `openr.install-keybind`: append the default bindings to config.toml
# (prefix+o → pick-visible, prefix+shift+o → pick-transcript) unless openr is
# already bound or a key is taken, then reload.
set -uo pipefail

herdr_bin="${HERDR_BIN_PATH:-herdr}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/herdr/config.toml"

toast() { "$herdr_bin" notification show "openr" --body "$1" 2>/dev/null; }
# on server startup runs, stay silent unless we actually change something
quiet="${HERDR_PLUGIN_EVENT:-}"

if grep -q 'command = "openr.pick' "$config" 2>/dev/null; then
  [ "$quiet" = "startup" ] || toast "already bound — nothing to do"
  exit 0
fi
for key in "prefix+o" "prefix+shift+o"; do
  if grep -q "key = \"$key\"" "$config" 2>/dev/null; then
    toast "$key is taken — bind openr manually in config.toml"
    exit 1
  fi
done

cat >> "$config" <<'EOF'

# openr: fuzzy-open recent file paths / URLs from the current pane
[[keys.command]]
key = "prefix+o"
type = "plugin_action"
command = "openr.pick-visible"
description = "open file/URL from visible pane"

[[keys.command]]
key = "prefix+shift+o"
type = "plugin_action"
command = "openr.pick-transcript"
description = "open file/URL from Claude transcript"
EOF

if "$herdr_bin" server reload-config >/dev/null 2>&1; then
  toast "bound prefix+o (visible) and prefix+shift+o (transcript)"
else
  toast "keybinds written, but reload-config failed — run: herdr server reload-config"
  exit 1
fi
