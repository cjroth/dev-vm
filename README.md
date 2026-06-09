# dev-vm

My reproducible **OrbStack Linux dev machine**, provisioned from a single
cloud-init file — plus a bridge that lets an MCP server **inside** the VM drive
**Firefox running on the Mac**.

## Contents

| Path | Runs on | What it is |
| --- | --- | --- |
| `dev-setup.cloud-init.yml` | VM (at first boot) | cloud-config: user, packages, dev toolchain (bun, Rust, starship, Claude Code, rtk), git/SSH signing, and the Firefox→MCP relay service. |
| `mac/firefox-mcp.sh` | **Mac (host)** | Launches Firefox with Marionette so the in-VM MCP can attach. |

## Provision the VM

Create an OrbStack machine using `dev-setup.cloud-init.yml` as the cloud-init
user data, e.g.:

```bash
orbctl create ubuntu dev --user-data ./dev-setup.cloud-init.yml
# (use whatever distro/name you like; check `orb create --help` for the flag)
```

Change the `chris` username near the top of the YAML to your macOS account name
if it differs. On first boot it installs the toolchain and, for the Firefox
bridge, the `socat` package + a `marionette-relay` systemd service.

---

## Firefox DevTools MCP bridge

Goal: use [`@mozilla/firefox-devtools-mcp`](https://github.com/mozilla/firefox-devtools-mcp)
from Claude Code **inside the VM** to automate the **real Firefox on your Mac**
(your profile, logins, tabs).

### Why a relay is needed

The MCP's `--connectExisting` mode spawns geckodriver, which connects to
Firefox's Marionette at a hardcoded **`127.0.0.1:2828`** (there's a port flag but
no host flag), and Marionette only binds the Mac's loopback. OrbStack already
forwards the Mac's localhost into the VM as `host.docker.internal`, so a tiny
relay closes the last gap:

```
Mac:  Firefox --marionette            ->  127.0.0.1:2828 (Mac loopback)
                                              ^  OrbStack forwards Mac localhost
VM:   socat 127.0.0.1:2828 ───────────────────┘   (marionette-relay.service)
        ^
VM:   geckodriver (firefox-devtools MCP)  dials  127.0.0.1:2828
```

The relay (`marionette-relay.service`) and the MCP registration are both set up
by `dev-setup.cloud-init.yml`. No SSH tunnel — OrbStack's SSH proxy rejects
remote (`-R`) forwards anyway.

### Each session: start Firefox on the Mac

Run the launcher **on the Mac** (it no-ops if Marionette is already up):

```bash
./mac/firefox-mcp.sh
```

It quits/relaunches Firefox Nightly with `--marionette --remote-allow-system-access`
(restoring your tabs). The system-access flag is what lets the MCP open DevTools
and use privileged-context tools. Override the binary with
`FIREFOX_BIN=/Applications/Firefox.app/Contents/MacOS/firefox FIREFOX_APP=Firefox`.

**Where to keep it on the Mac:** clone this repo somewhere stable (e.g.
`~/Developer/dev-vm`) and run it from there so it stays version-controlled. For a
short command, symlink it onto your PATH:

```bash
ln -s "$PWD/mac/firefox-mcp.sh" ~/.local/bin/firefox-mcp   # then: firefox-mcp
```

### Use it from the VM

The MCP is registered (user scope) as `firefox-devtools` by the cloud-init. It
needs Node.js at runtime (for `npx`). To register manually:

```bash
claude mcp add firefox-devtools -s user -- \
  npx -y @mozilla/firefox-devtools-mcp@latest --connectExisting --marionettePort 2828
```

Then in Claude Code call `list_pages`, `navigate_page`, `take_snapshot`,
`screenshot_page`, etc. Quick check that the relay path is live:

```bash
systemctl status marionette-relay              # relay health
nc -z 127.0.0.1 2828 && echo "marionette reachable"
```

### Notes

- Marionette sets `navigator.webdriver=true` and alters fingerprinting — some
  sites (Cloudflare/Akamai) may flag the browser. Restart Firefox normally when
  you're done automating.
- Restarting `marionette-relay` drops any active automation session.
- Change the port consistently in three places if 2828 conflicts: the service,
  the MCP registration (`--marionettePort`), and `firefox-mcp.sh`
  (`MARIONETTE_PORT`).
