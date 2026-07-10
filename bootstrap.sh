#!/usr/bin/env bash
#
# bootstrap.sh — one command to provision a fresh Mac from this repo.
#
# dev-vm is PRIVATE, so GH_TOKEN is required just to fetch and clone it. The
# token is used only to clone; the origin remote is then reset to SSH (the key
# dev-setup.sh generates + uploads takes over from there).
#
# Run from a fresh Mac (Terminal.app), pasting your token(s) inline:
#
#   curl -fsSL -H "Authorization: token $GH_TOKEN" \
#     https://raw.githubusercontent.com/cjroth/dev-vm/main/bootstrap.sh \
#     | GH_TOKEN="$GH_TOKEN" CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_CODE_OAUTH_TOKEN" bash
#
#   GH_TOKEN               required — a GitHub token with `repo` read (clone) +
#                          admin:public_key (dev-setup.sh uploads the SSH key).
#   CLAUDE_CODE_OAUTH_TOKEN optional — logs Claude Code in headlessly. Generate
#                          once on a machine with a browser: `claude setup-token`.
#
set -uo pipefail

REPO="${REPO:-cjroth/dev-vm}"
BRANCH="${BRANCH:-main}"
DEST="${DEST:-$HOME/dev/dev-vm}"

c_grn=$'\033[32m'; c_red=$'\033[31m'; c_rst=$'\033[0m'
say() { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
die() { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

[ -n "${GH_TOKEN:-}" ] || die "GH_TOKEN is required (dev-vm is private). See the header of this script."

# Xcode Command Line Tools — provides git. Absent on a truly fresh Mac; the
# installer is a GUI prompt we can't drive, so trigger it and ask for a re-run.
if ! xcode-select -p >/dev/null 2>&1; then
  say "Triggering Xcode Command Line Tools install — accept the GUI dialog..."
  xcode-select --install >/dev/null 2>&1 || true
  die "Re-run this command once Command Line Tools finish installing."
fi

# Clone (token over HTTPS) or update an existing checkout.
mkdir -p "$(dirname "$DEST")"
if [ -d "$DEST/.git" ]; then
  say "Updating existing clone at $DEST..."
  git -C "$DEST" pull --ff-only || true
else
  say "Cloning $REPO -> $DEST..."
  git clone --branch "$BRANCH" \
    "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git" "$DEST" \
    || die "Clone failed — check that GH_TOKEN has 'repo' read scope."
fi

# Don't leave the token embedded in .git/config; hand off to SSH.
git -C "$DEST" remote set-url origin "git@github.com:${REPO}.git" 2>/dev/null || true

say "Handing off to mac/dev-setup.sh..."
# GH_TOKEN + CLAUDE_CODE_OAUTH_TOKEN are inherited from the environment.
exec "$DEST/mac/dev-setup.sh"
