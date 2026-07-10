#!/usr/bin/env bash
#
# dev-setup.sh  —  run this ON A macOS MACHINE (a fresh Tart VM, or any Mac).
#
# The macOS counterpart to ../dev-setup.cloud-init.yml. Provisions the same
# toolchain — bun, Node, Python, Rust, starship, Claude Code, rtk — plus
# SSH-signing git config, using Homebrew + mise instead of apt/cloud-init.
#
# Assumes an admin user with passwordless (or cached) sudo and Xcode Command
# Line Tools present — both true on cirruslabs `macos-*-base` Tart images.
#
# Usage (fresh VM, over SSH):
#   CLAUDE_CODE_OAUTH_TOKEN=<token> GH_TOKEN=<token> ./mac/dev-setup.sh
#
# Both tokens are optional; omit them to fall through to manual instructions.
# Get a 1-year Claude token on a browser machine with:  claude setup-token
#
# No `set -e` — we want one failing installer not to abort the rest.
set -uo pipefail

c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_rst=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*"; }

ZSHRC="$HOME/.zshrc"

# Helper: append a line to ~/.zshrc only if not already present
append_zshrc() {
  grep -qxF "$1" "$ZSHRC" 2>/dev/null || echo "$1" >> "$ZSHRC"
}

# Helper: append a multi-line block to ~/.zshrc only if marker not present
append_zshrc_block() {
  local marker="$1" content="$2"
  grep -qxF "# >>> $marker >>>" "$ZSHRC" 2>/dev/null || cat >> "$ZSHRC" << EOF

# >>> $marker >>>
$content
# <<< $marker <<<
EOF
}

# ---------------------------------------------------------------------------
# Homebrew — the base package manager (Apple Silicon prefix: /opt/homebrew)
# ---------------------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  say "Installing Homebrew..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
BREW="$( [ -x /opt/homebrew/bin/brew ] && echo /opt/homebrew/bin/brew || echo /usr/local/bin/brew )"
eval "$("$BREW" shellenv)"
append_zshrc "eval \"\$($BREW shellenv)\""

# CLI tooling (Node/Python come from mise below, not brew, so versions pin)
say "Installing CLI tools via brew..."
brew install git gh mise starship ripgrep fd jq fzf

# ---------------------------------------------------------------------------
# mise — pinned, per-project-overridable Node + Python (+ more)
# ---------------------------------------------------------------------------
append_zshrc_block "mise" 'eval "$(mise activate zsh)"'
eval "$("$BREW" --prefix)/bin/mise activate bash" 2>/dev/null || true
say "Pinning Node + Python via mise..."
mise use -g node@lts
mise use -g python@3.13

# ---------------------------------------------------------------------------
# bun (official installer — mirrors the Linux setup; installs to ~/.bun)
# ---------------------------------------------------------------------------
say "Installing bun..."
curl -fsSL https://bun.com/install | bash
append_zshrc 'export PATH="$HOME/.bun/bin:$PATH"'

# ---------------------------------------------------------------------------
# Rust (rustup, non-interactive, accept defaults; installs to ~/.cargo)
# ---------------------------------------------------------------------------
say "Installing Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
append_zshrc 'export PATH="$HOME/.cargo/bin:$PATH"'

# ---------------------------------------------------------------------------
# starship prompt + config (same one-line prompt as the Linux setup)
# ---------------------------------------------------------------------------
append_zshrc_block "starship" 'eval "$(starship init zsh)"'
mkdir -p "$HOME/.config"
cat > "$HOME/.config/starship.toml" << 'TOML'
[container]
disabled = true

[username]
disabled = true

[rust]
disabled = true

[bun]
disabled = true

[nodejs]
disabled = true

[python]
disabled = true

[package]
disabled = true

[hostname]
ssh_only = false
format = "[$hostname]($style) / "

[directory]
format = "[$path]($style)[$read_only]($read_only_style) "

[git_branch]
symbol = ""
format = "/ [$branch]($style) "

[line_break]
disabled = true
TOML

# Kill the process on a given port: bye <port>
append_zshrc_block "bye function" 'bye() {
  local pid
  pid=$(lsof -ti :"$1") || { echo "Nothing running on port $1"; return 1; }
  kill "$pid" && echo "Killed process $pid on port $1"
}'

# ---------------------------------------------------------------------------
# Claude Code
# ---------------------------------------------------------------------------
say "Installing Claude Code..."
curl -fsSL https://claude.ai/install.sh | bash
append_zshrc 'export PATH="$HOME/.local/bin:$PATH"'

# Configure Claude Code settings (mirrors the live ~/.claude/settings.json:
# bypass permissions, no Claude attribution in commits, Opus 1M default,
# fullscreen TUI, auto theme).
mkdir -p ~/.claude
cat > ~/.claude/settings.json << 'JSON'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "defaultMode": "bypassPermissions"
  },
  "skipDangerousModePermissionPrompt": true,
  "includeCoAuthoredBy": false,
  "attribution": {
    "commit": "",
    "pr": ""
  },
  "model": "opus[1m]",
  "tui": "fullscreen",
  "theme": "auto"
}
JSON

# Auth: macOS stores the interactive /login in the Keychain, which is machine-
# bound and CANNOT be baked into an image. Instead we use a long-lived OAuth
# token (valid ~1 year, tied to your Pro/Max subscription). Generate it once on
# a machine with a browser via `claude setup-token`, then pass it in the env.
if [ -n "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  ( umask 077; printf 'export CLAUDE_CODE_OAUTH_TOKEN=%q\n' "$CLAUDE_CODE_OAUTH_TOKEN" > "$HOME/.claude-token.sh" )
  append_zshrc '[ -f "$HOME/.claude-token.sh" ] && source "$HOME/.claude-token.sh"'
  say "Claude Code: OAuth token installed (subscription auth, ~1yr)."
else
  warn "CLAUDE_CODE_OAUTH_TOKEN not set — Claude Code installed but NOT logged in."
  warn "  Get a 1-year token on a browser machine:   claude setup-token"
  warn "  Then re-run:  CLAUDE_CODE_OAUTH_TOKEN=<token> ./mac/dev-setup.sh"
  warn "  Or just run 'claude' in the VM and use /login interactively."
fi

# ---------------------------------------------------------------------------
# rtk (disable telemetry)
# ---------------------------------------------------------------------------
say "Installing rtk..."
curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/refs/heads/master/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"  # so rtk is callable in this script
echo "n" | rtk init -g --auto-patch
append_zshrc 'export RTK_TELEMETRY_DISABLED=1'

# ---------------------------------------------------------------------------
# git: SSH key + commit signing + identity
# ---------------------------------------------------------------------------
SSH_KEY="$HOME/.ssh/id_ed25519"
if [ ! -f "$SSH_KEY" ]; then
  mkdir -p ~/.ssh && chmod 700 ~/.ssh
  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)" -f "$SSH_KEY" -N ""
fi

# Trust github.com host key (avoids the "yes/no" prompt on first ssh)
if ! grep -q "^github.com " ~/.ssh/known_hosts 2>/dev/null; then
  ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts 2>/dev/null
fi

# Sign commits with the SSH key
git config --global gpg.format ssh
git config --global user.signingkey "$SSH_KEY.pub"
git config --global commit.gpgsign true
git config --global tag.gpgsign true

# git identity (email must match a verified GitHub email)
git config --global user.name "Chris Roth"
git config --global user.email "chris@cjroth.com"

# Trusted signers for local verification
mkdir -p ~/.config/git
echo "$(git config --global user.email) $(cat "$SSH_KEY.pub")" > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers

# Upload the key to GitHub if a token is available; else print instructions.
if [ -n "${GH_TOKEN:-}" ]; then
  echo "$GH_TOKEN" | gh auth login --with-token
  gh auth setup-git
  gh ssh-key add "$SSH_KEY.pub" --title "mac-dev-$(hostname)-auth"
  gh ssh-key add "$SSH_KEY.pub" --title "mac-dev-$(hostname)-signing" --type signing
else
  echo
  warn "GH_TOKEN not set — skipping gh auth and key upload."
  warn "Add this key at https://github.com/settings/ssh/new (once as Authentication, once as Signing):"
  cat "$SSH_KEY.pub"
  echo
fi

# ---------------------------------------------------------------------------
# Terminal.app — make Option+Enter insert a newline in the Claude Code TUI
# ---------------------------------------------------------------------------
# Mirrors Claude Code's `/terminal-setup`. Terminal.app can't tell Shift+Enter
# apart from a plain Enter, so the supported trick is "Use Option as Meta key":
# Option+Enter then sends the Meta+Enter sequence Claude Code reads as a newline.
# Also switches the bell to visual. Self-skips on hosts without Terminal.app
# (e.g. a headless VM) — there, run `/terminal-setup` inside Claude Code, and on
# iTerm2 / the VS Code terminal use that same command to bind Shift+Enter.
# PlistBuddy can't address the space in the "Window Settings" key, so edit the
# plist with python3 (ships with the Command Line Tools this script requires).
configure_terminal() {
  local plist="$HOME/Library/Preferences/com.apple.Terminal.plist"
  [ -f "$plist" ] || { warn "Terminal.app prefs not found — skipping newline config (run /terminal-setup in Claude Code)."; return 0; }
  say "Configuring Terminal.app (Option=Meta so Option+Enter = newline, visual bell)..."
  /usr/bin/python3 - "$plist" <<'PY' || { warn "Terminal config skipped (plist edit failed)."; return 0; }
import sys, plistlib
path = sys.argv[1]
with open(path, 'rb') as f:
    d = plistlib.load(f)
profile = d.get('Default Window Settings', 'Basic')
prof = d.get('Window Settings', {}).get(profile)
if prof is None:
    print(f"  profile {profile!r} not found; skipping"); sys.exit(0)
prof['useOptionAsMetaKey'] = True   # Option+Enter -> newline
prof['Bell'] = False                # audible bell off
prof['VisualBell'] = True           # visual bell on
with open(path, 'wb') as f:
    plistlib.dump(d, f)
print(f"  configured profile {profile!r}")
PY
  killall cfprefsd 2>/dev/null || true
  warn "Restart Terminal.app for the newline binding to take effect (Option+Enter = newline)."
}
configure_terminal

say "Done. Open a new shell (or 'exec zsh') to pick up PATH, mise, starship, and the prompt."
