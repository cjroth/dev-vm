# dev-vm

My reproducible dev machines — an **OrbStack Linux** box provisioned from a
single cloud-init file, and a **macOS (Tart) VM** provisioned from an equivalent
shell script — plus a bridge that lets an MCP server **inside** the Linux VM
drive **Firefox running on the Mac**.

## Contents

| Path | Runs on | What it is |
| --- | --- | --- |
| `dev-setup.cloud-init.yml` | Linux VM (at first boot) | cloud-config: user, packages, dev toolchain (bun, Rust, starship, Claude Code, rtk), git/SSH signing, and the Firefox→MCP relay service. |
| `mac/dev-setup.sh` | **macOS / Tart VM** | Provisioner for a Mac box — the macOS analog of the cloud-init. Same toolchain (bun, Node + Python via mise, Rust, starship, Claude Code, rtk) + SSH-signing git, via Homebrew. |
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

## Provision a Mac VM (Tart)

For a macOS box — a fresh [Tart](https://tart.run) VM, or any Mac —
`mac/dev-setup.sh` installs the same toolchain as the Linux cloud-init using
Homebrew + [mise](https://mise.jdx.dev). It assumes an admin user with sudo and
Xcode Command Line Tools, both present on the cirruslabs `macos-*-base` images.

```bash
tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest dev
tart run dev &
ssh admin@"$(tart ip dev)" \
  'git clone git@github.com:cjroth/dev-vm.git && \
   CLAUDE_CODE_OAUTH_TOKEN=<token> GH_TOKEN=<token> ./dev-vm/mac/dev-setup.sh'
```

Both tokens are optional:

- **`CLAUDE_CODE_OAUTH_TOKEN`** logs Claude Code in without a browser. macOS keeps
  the interactive `/login` in the machine-bound Keychain, so it can't be baked
  into an image — generate a ~1-year token once on a machine with a browser
  (`claude setup-token`) and pass it in. Omit it and Claude Code installs but
  stays logged out (run `claude` then `/login` later).
- **`GH_TOKEN`** uploads the generated SSH key to GitHub (once as Authentication,
  once as Signing). Omit it and the script prints the public key for you to add
  manually.

> **Don't update macOS in-place inside the VM.** OTA update *personalization*
> fails in virtualized macOS (the installer's hardware checks hit null values).
> Bump the OS by cloning a newer `macos-*-base` image and re-running this script.

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
