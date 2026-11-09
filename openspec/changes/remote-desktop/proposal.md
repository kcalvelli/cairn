# Proposal

## Why

Cairn hosts have no way to get a graphical session remotely. Monitorless servers like mini can't be used at a desktop at all, and getting to your own desktop on another machine means walking over to it. Cairn needs fleet-wide remote desktop: any cairn user can open a **fresh** niri session on any cairn host, from anywhere on the tailnet, without anyone being logged in at the machine.

Off-the-shelf options don't fit niri. GNOME Remote Desktop needs `org.gnome.Mutter.RemoteDesktop`, and niri only implements `Mutter.ScreenCast`. xrdp is X11-only. Sunshine attaches to the physical display and injects input through a seat-wide uinput device. So cairn has to put the pieces together itself.

## What Changes

- New flagged NixOS module `remote-desktop` (`modules.remoteDesktop = true` in host config) that serves per-user, on-demand headless niri sessions over VNC.
- Each session is a niri instance nested inside a headless `cage` host compositor, started as a real logind session for the target user (PAM, `pam_systemd`) the first time someone connects. It keeps running across disconnects until the user logs out.
- `wayvnc` attaches to the nested niri and serves it over a per-session Unix socket. A per-user systemd socket on the Tailscale interface forwards connections to it via `systemd-socket-proxyd`.
- Authentication is VeNCrypt (TLS) with PAM, so only the session owner's own password unlocks their session. A self-signed TLS certificate is generated per host on first use.
- Network exposure is the Tailscale interface only: sockets bind to `tailscale0` and the firewall opens the ports there and nowhere else. The module asserts that Tailscale is enabled.
- New per-user option `cairn.users.users.<name>.remoteDesktop.port`. User files are shared across hosts, so a user's port is the same everywhere in the fleet. Ports must be unique per host.
- Portal-safe session roles. A remote session runs niri with `--session` (taking over the GNOME portal backends and the user's activation environment) only when the user has no other graphical session on that host. Otherwise it runs isolated and leaves the local session's environment alone.
- The niri startup environment import (`home/desktop/niri.nix`) is wrapped so it does nothing inside an isolated remote session.
- Client side: `cairn.remoteDesktop.client.enable` installs Remmina and a `cairn-remote <host> [--user <name>]` launcher on desktop hosts.

## Capabilities

### New Capabilities
- `remote-desktop`: on-demand, per-user headless niri sessions served over authenticated VNC on the tailnet, including session lifecycle, network exposure, authentication, portal and session-role behaviour, and the client launcher.

### Modified Capabilities
- `multi-user`: the `cairn.users.users.<name>` submodule gains a `remoteDesktop.port` option. The port is declared once per user and applies on every host.
- `desktop`: the niri session's startup environment import becomes conditional, so a secondary (isolated) session doesn't retarget the user's systemd/D-Bus activation environment.

## Impact

- **New code**: `modules/remote-desktop/default.nix` (server, sockets, PAM service, firewall, cert generation, session launcher), registered in `modules/default.nix` and as a flagged module in `lib/default.nix`.
- **Modified**: `modules/users.nix` (new per-user option), `home/desktop/niri.nix` (conditional env import), `home/desktop/normie.nix` if it carries the same spawn, and `scripts/init-config.sh` / templates (offer the flag).
- **Dependencies (nixpkgs)**: `cage`, `wayvnc`, `wlr-randr`, `remmina` (client), `openssl` (cert generation). No new flake inputs.
- **Hosts**: no effect unless `modules.remoteDesktop` is set. When it is, each user's port opens on `tailscale0` only.
- **Known limits (v1)**: no audio; fixed session resolution (configurable, no client-driven resize); in an isolated secondary session, portal dialogs and screencasts go to the user's local session.
- **Out of scope**: attaching to an existing local session, exposure outside the tailnet, game streaming. Sunshine/Moonlight is a reasonable separate capability for that later.
