#!/bin/sh
# claude-bell — make Claude Code ping your terminal when it needs attention or finishes.
#
# What it does: merges two hooks (Notification + Stop) into your Claude Code
# settings.json. The hook is a self-contained one-liner that rings the terminal
# bell — no extra files are installed. Works locally and over SSH, on any OS whose
# terminal makes a sound for the bell character.
#
# Usage:   sh install.sh
#   or:    curl -fsSL https://raw.githubusercontent.com/<you>/claude-bell/main/install.sh | sh
#
# Re-running is safe (idempotent). To remove: sh uninstall.sh
set -eu

# --- config -----------------------------------------------------------------
BEEPS=2                          # number of beeps per ping
GAP=0.3                          # seconds between beeps
MARKER="claude-bell"            # tag embedded in the hook command (for idempotency/uninstall)

CFG="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CFG/settings.json"

# The inline bell command written into settings.json.
# `: claude-bell;` is a shell no-op that tags this hook so we can find/replace it later.
# Claude runs hooks detached (no controlling terminal), so /dev/tty is often gone.
# Build an ordered list of candidate terminals and ring the first that accepts a write:
#   1. $SSH_TTY                        (remote / SSH, Linux + macOS)
#   2. ancestor terminals, found by walking parent PIDs; for each tty value `d` we try
#      both /dev/$d (Linux -> /dev/pts/0) and /dev/tty$d (macOS: d=s000 -> /dev/ttys000)
#   3. /dev/tty                        (Git Bash/MSYS, mintty, real controlling ttys)
#   4. stdout                          (last-resort, harmless if nothing else worked)
CMD=": $MARKER; ring(){ n=0; while [ \"\$n\" -lt $BEEPS ]; do printf '\\a' > \"\$1\" 2>/dev/null || return 1; sleep $GAP; n=\$((n+1)); done; }; cands=\"\"; [ -n \"\${SSH_TTY:-}\" ] && cands=\"\$SSH_TTY\"; p=\$PPID; while [ -n \"\$p\" ] && [ \"\$p\" != 0 ]; do d=\$(ps -o tty= -p \"\$p\" 2>/dev/null | tr -d ' '); case \"\$d\" in ''|*\\?*) ;; *) cands=\"\$cands /dev/\$d /dev/tty\$d\";; esac; p=\$(ps -o ppid= -p \"\$p\" 2>/dev/null | tr -d ' '); done; cands=\"\$cands /dev/tty\"; rung=0; set -f; for t in \$cands; do [ -w \"\$t\" ] && ring \"\$t\" && { rung=1; break; }; done; set +f; [ \"\$rung\" = 1 ] || printf '\\a'"

# --- prep -------------------------------------------------------------------
mkdir -p "$CFG"
if [ ! -s "$SETTINGS" ]; then
  printf '{}\n' > "$SETTINGS"
  echo "Created $SETTINGS"
else
  BACKUP="$SETTINGS.bak.$(date +%s 2>/dev/null || echo backup)"
  cp "$SETTINGS" "$BACKUP"
  echo "Backed up existing settings -> $BACKUP"
fi

# --- merge ------------------------------------------------------------------
# Strategy: drop any prior claude-bell hooks (so re-running updates cleanly),
# then add fresh Notification + Stop entries. Pick the first available engine.

merge_with_jq() {
  tmp="$SETTINGS.tmp.$$"
  jq --arg cmd "$CMD" --arg m "$MARKER" '
    def strip(arr): (arr // []) | map(select((.hooks // []) | any(.command // "" | contains($m)) | not));
    .hooks //= {} |
    .hooks.Notification = strip(.hooks.Notification) + [ { matcher: "", hooks: [ { type: "command", command: $cmd } ] } ] |
    .hooks.Stop         = strip(.hooks.Stop)         + [ {              hooks: [ { type: "command", command: $cmd } ] } ]
  ' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
}

merge_with_python() {
  CB_SETTINGS="$SETTINGS" CB_CMD="$CMD" CB_MARKER="$MARKER" "$1" - <<'PY'
import json, os, sys
path = os.environ["CB_SETTINGS"]; cmd = os.environ["CB_CMD"]; marker = os.environ["CB_MARKER"]
try:
    with open(path) as f: data = json.load(f)
except (ValueError, FileNotFoundError):
    data = {}
if not isinstance(data, dict): data = {}
hooks = data.setdefault("hooks", {})

def strip(arr):
    out = []
    for entry in (arr or []):
        subs = entry.get("hooks", []) if isinstance(entry, dict) else []
        if any(marker in (s.get("command", "") or "") for s in subs): continue
        out.append(entry)
    return out

hooks["Notification"] = strip(hooks.get("Notification")) + [
    {"matcher": "", "hooks": [{"type": "command", "command": cmd}]}]
hooks["Stop"] = strip(hooks.get("Stop")) + [
    {"hooks": [{"type": "command", "command": cmd}]}]

with open(path, "w") as f:
    json.dump(data, f, indent=2); f.write("\n")
PY
}

merge_with_node() {
  CB_SETTINGS="$SETTINGS" CB_CMD="$CMD" CB_MARKER="$MARKER" node - <<'JS'
const fs = require("fs");
const path = process.env.CB_SETTINGS, cmd = process.env.CB_CMD, marker = process.env.CB_MARKER;
let data = {};
try { data = JSON.parse(fs.readFileSync(path, "utf8")); } catch (e) { data = {}; }
if (typeof data !== "object" || data === null || Array.isArray(data)) data = {};
const hooks = data.hooks = data.hooks || {};
const strip = (arr) => (arr || []).filter(e =>
  !((e && e.hooks) || []).some(s => (s.command || "").includes(marker)));
hooks.Notification = strip(hooks.Notification).concat([{ matcher: "", hooks: [{ type: "command", command: cmd }] }]);
hooks.Stop = strip(hooks.Stop).concat([{ hooks: [{ type: "command", command: cmd }] }]);
fs.writeFileSync(path, JSON.stringify(data, null, 2) + "\n");
JS
}

if command -v jq >/dev/null 2>&1; then
  merge_with_jq
elif command -v python3 >/dev/null 2>&1; then
  merge_with_python python3
elif command -v python >/dev/null 2>&1; then
  merge_with_python python
elif command -v node >/dev/null 2>&1; then
  merge_with_node
else
  cat <<EOF
! No jq, python, or node found — can't edit JSON automatically.
  Add these two hooks to $SETTINGS under "hooks" manually:

  "Notification": [ { "matcher": "", "hooks": [ { "type": "command", "command": "$CMD" } ] } ],
  "Stop":         [ {               "hooks": [ { "type": "command", "command": "$CMD" } ] } ]
EOF
  exit 1
fi

# --- verify + done ----------------------------------------------------------
if command -v jq >/dev/null 2>&1; then
  jq empty "$SETTINGS" >/dev/null 2>&1 || { echo "! Resulting settings.json is invalid JSON"; exit 1; }
elif command -v python3 >/dev/null 2>&1; then
  python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$SETTINGS" >/dev/null 2>&1 || { echo "! invalid JSON"; exit 1; }
fi

echo "✓ Installed bell hooks into $SETTINGS (Notification + Stop)."
echo "  Restart Claude Code (or start a new session) to load them."

# fire a test ping using the exact same candidate-resolution as the installed hook
ring(){ n=0; while [ "$n" -lt "$BEEPS" ]; do printf '\a' > "$1" 2>/dev/null || return 1; sleep "$GAP"; n=$((n+1)); done; }
cands=""; [ -n "${SSH_TTY:-}" ] && cands="$SSH_TTY"
p=$PPID
while [ -n "$p" ] && [ "$p" != 0 ]; do
  d=$(ps -o tty= -p "$p" 2>/dev/null | tr -d ' ')
  case "$d" in ''|*\?*) ;; *) cands="$cands /dev/$d /dev/tty$d";; esac
  p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
done
cands="$cands /dev/tty"
rung=0; set -f; for t in $cands; do [ -w "$t" ] && ring "$t" && { rung=1; break; }; done; set +f
[ "$rung" = 1 ] || printf '\a'
echo "  (sent a test ping — hear nothing? enable your terminal's audible bell.)"
