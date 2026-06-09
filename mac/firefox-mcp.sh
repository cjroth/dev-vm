#!/usr/bin/env bash
#
# firefox-mcp.sh  —  run this ON YOUR MAC (the host), not in the VM.
#
# Ensures Firefox is running with Marionette so the firefox-devtools MCP
# server inside the OrbStack VM can drive it.
#
# No SSH tunnel is needed: OrbStack already forwards the Mac's localhost to
# the VM (reachable there as host.docker.internal). The "marionette-relay"
# systemd service provisioned by dev-setup.cloud-init.yml bridges the VM's
# 127.0.0.1:2828 to the Mac. So the ONLY thing the Mac needs is Firefox
# listening on 127.0.0.1:2828.
#
#   Mac Firefox (--marionette) 127.0.0.1:2828
#        ^  OrbStack host.docker.internal
#   VM  socat relay  ->  VM 127.0.0.1:2828  <-  geckodriver (firefox-devtools MCP)
#
# Usage:  ./firefox-mcp.sh
#
# Env overrides:
#   FIREFOX_BIN   path to the Firefox binary (default: Firefox Nightly)
#   FIREFOX_APP   macOS app name for open/quit (default: "Firefox Nightly")
#   MARIONETTE_PORT  default 2828 (match the MCP + relay if you change it)
set -uo pipefail

PORT="${MARIONETTE_PORT:-2828}"
FIREFOX="${FIREFOX_BIN:-/Applications/Firefox Nightly.app/Contents/MacOS/firefox}"
FIREFOX_APP="${FIREFOX_APP:-Firefox Nightly}"

c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_red=$'\033[31m'; c_rst=$'\033[0m'
say()  { printf '%s==>%s %s\n' "$c_grn" "$c_rst" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yel" "$c_rst" "$*"; }
die()  { printf '%s[x]%s %s\n' "$c_red" "$c_rst" "$*" >&2; exit 1; }

[[ -x "$FIREFOX" ]] || die "Firefox not found at: $FIREFOX  (set FIREFOX_BIN=/path/to/firefox)"

marionette_up() { nc -z -G 1 127.0.0.1 "$PORT" >/dev/null 2>&1; }

if marionette_up; then
  say "Marionette already listening on 127.0.0.1:${PORT}. You're good to go."
  exit 0
fi

if pgrep -x firefox >/dev/null; then
  warn "Firefox is running WITHOUT Marionette; it must be restarted with --marionette."
  read -r -p "    Quit & relaunch ${FIREFOX_APP} now? Tabs will be restored. [y/N] " ans
  [[ "$ans" == [yY]* ]] || die "Aborted. Quit Firefox yourself, then re-run, or start it with: $FIREFOX --marionette --remote-allow-system-access"
  say "Quitting ${FIREFOX_APP}..."
  osascript -e "quit app \"${FIREFOX_APP}\"" >/dev/null 2>&1 || true
  for _ in $(seq 1 20); do pgrep -x firefox >/dev/null || break; sleep 0.5; done
  pgrep -x firefox >/dev/null && die "Firefox didn't quit; close it manually and re-run."
fi

say "Launching ${FIREFOX_APP} with Marionette (port ${PORT}) + system access..."
# --remote-allow-system-access lets Marionette enter the chrome/system context,
# needed to open DevTools and to use the MCP's privileged-context tools.
open -na "$FIREFOX_APP" --args --marionette --marionette-port "$PORT" --remote-allow-system-access
for _ in $(seq 1 40); do marionette_up && break; sleep 0.5; done
marionette_up || die "Marionette never came up on ${PORT}. Check Firefox started OK."

say "Marionette is up on 127.0.0.1:${PORT}. The MCP server in the VM can now drive Firefox."
warn "Marionette sets navigator.webdriver=true and alters fingerprinting; some sites"
warn "(Cloudflare/Akamai) may flag the browser. Restart Firefox normally when done."
