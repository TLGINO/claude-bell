#!/bin/sh
# claude-bell — remove the bell hooks added by install.sh.
# Strips only hooks tagged with the claude-bell marker; leaves all your other hooks alone.
set -eu

MARKER="claude-bell"
CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"

[ -s "$SETTINGS" ] || { echo "No settings file at $SETTINGS — nothing to do."; exit 0; }

BACKUP="$SETTINGS.bak.$(date +%s 2>/dev/null || echo backup)"
cp "$SETTINGS" "$BACKUP"
echo "Backed up -> $BACKUP"

strip_with_jq() {
  tmp="$SETTINGS.tmp.$$"
  jq --arg m "$MARKER" '
    def strip(arr): (arr // []) | map(select((.hooks // []) | any(.command // "" | contains($m)) | not));
    if .hooks then
      .hooks.Notification = strip(.hooks.Notification) |
      .hooks.Stop         = strip(.hooks.Stop)
    else . end
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

strip_with_python() {
  CB_SETTINGS="$SETTINGS" CB_MARKER="$MARKER" "$1" - <<'PY'
import json, os
path = os.environ["CB_SETTINGS"]; marker = os.environ["CB_MARKER"]
with open(path) as f: data = json.load(f)
hooks = data.get("hooks") if isinstance(data, dict) else None
def strip(arr):
    out = []
    for e in (arr or []):
        subs = e.get("hooks", []) if isinstance(e, dict) else []
        if any(marker in (s.get("command","") or "") for s in subs): continue
        out.append(e)
    return out
if hooks:
    for ev in ("Notification", "Stop"):
        if ev in hooks: hooks[ev] = strip(hooks[ev])
with open(path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
PY
}

if command -v jq >/dev/null 2>&1; then
  strip_with_jq
elif command -v python3 >/dev/null 2>&1; then
  strip_with_python python3
elif command -v python >/dev/null 2>&1; then
  strip_with_python python
else
  echo "! Need jq or python to edit JSON. Remove the claude-bell hooks from $SETTINGS by hand."
  exit 1
fi

echo "✓ Removed claude-bell hooks from $SETTINGS."
