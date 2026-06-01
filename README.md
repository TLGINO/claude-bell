# 🔔 claude-bell

A tiny ping for [Claude Code](https://claude.com/claude-code). Get a small bell
sound the moment Claude **needs your attention** or **finishes a task** — so you
can look away and come back when it matters.

- **One script.** No files copied around — the bell logic lives inline in your
  `settings.json` hook.
- **Works over SSH.** The bell travels through your terminal, so a Claude session
  on a remote server still pings *your* laptop.
- **Any OS.** macOS, Linux, Windows (WSL / Git Bash) — the sound is made by your
  local terminal, not the machine Claude runs on.

## Install

```sh
curl -fsSL https://raw.githubusercontent.com/TLGINO/claude-bell/master/install.sh | sh
```

or clone and run:

```sh
sh install.sh
```

Then restart Claude Code (or start a new session). That's it.

## How it works

It adds two [hooks](https://docs.claude.com/en/docs/claude-code/hooks) to your
Claude Code `settings.json`:

- **`Notification`** → rings when Claude needs you (a permission prompt, idle input).
- **`Stop`** → rings when Claude finishes responding.

The hook command is a self-contained one-liner that writes the terminal bell
character to your terminal. Claude runs hooks **detached** — the hook subprocess
has no controlling terminal, so `/dev/tty` is usually gone
(`No such device or address`). So the bell builds an ordered list of candidate
terminals and rings the first one that accepts a write:

```sh
# 1. $SSH_TTY                     remote / SSH
# 2. ancestor terminals: walk parent PIDs (ps -o ppid=), read each tty (ps -o tty=);
#    try both /dev/$d (Linux -> /dev/pts/0) and /dev/tty$d (macOS s000 -> /dev/ttys000)
# 3. /dev/tty                     Git Bash/MSYS, mintty, real controlling ttys
# 4. stdout                       last resort
printf '\a' > "$t"   # ×2, with a short gap
```

This is why it works across OSes and over SSH: on a **remote** box `$SSH_TTY`
points back at your laptop's terminal; on a **local** session the ancestor walk
finds the `claude` process's terminal (`/dev/pts/0` etc.) that the detached hook
can't reach via `/dev/tty`.

## Configure

Edit the variables at the top of `install.sh` before running:

| Variable | Default | Meaning |
|----------|---------|---------|
| `BEEPS`  | `2`     | beeps per ping |
| `GAP`    | `0.3`   | seconds between beeps |

Respects `CLAUDE_CONFIG_DIR` if you've moved your Claude config.

## Hear nothing?

The script sends a test bell at the end of install. If it's silent, your local
**terminal emulator's audible bell is turned off**:

- **iTerm2**: Profiles → Terminal → uncheck *Silence bell*
- **Windows Terminal**: settings → `"bellStyle": "audible"`
- **GNOME Terminal / many Linux**: Preferences → Sound → enable *Terminal bell*
- **macOS Terminal.app**: Settings → Profiles → Advanced → *Audible bell*

## Uninstall

```sh
sh uninstall.sh
```

Removes only the bell hooks (tagged `claude-bell`); your other hooks are left
untouched. Both scripts back up `settings.json` before editing.

## Requirements

`jq`, `python3`/`python`, or `node` (any one) to edit the JSON. If none are
present, the installer prints the snippet to paste manually.

## License

MIT
