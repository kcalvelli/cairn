# Design

## Context

See `proposal.md` for the motivation. The facts below, checked on edge (niri 26.04), are what constrain the approach:

- niri owns `org.gnome.Mutter.ScreenCast`, `DisplayConfig`, `ServiceChannel`, `Shell.Introspect` and `Shell.Screenshot` on the user bus, but **not** `org.gnome.Mutter.RemoteDesktop`. Through `xdg-desktop-portal-gnome`, niri can be watched but not driven. Every GNOME-stack remote desktop server (gnome-remote-desktop, and the portal RemoteDesktop path that recent Sunshine and RustDesk use) dies here.
- niri does implement the wlroots protocols `zwlr_screencopy_manager_v1`, `zwlr_virtual_pointer_manager_v1` and `zwp_virtual_keyboard_manager_v1`. That's everything wayvnc needs.
- niri only claims those Mutter names, and only imports its environment into systemd and D-Bus, when started with `--session`. The user bus is per user, not per session, so two `--session` niris for one user fight over the same names and environment.
- Both cairn niri profiles also spawn `dbus-update-activation-environment --systemd --all` at startup (`home/desktop/niri.nix`, `home/desktop/normie.nix`). If a second session ran that, it would retarget the first session's activated apps.
- niri can run nested (winit backend) inside another Wayland compositor. Its headless backend exists in the source but has no supported runtime switch.
- DMS starts from niri's `spawn-at-startup` (systemd integration is off), so it comes up in any niri instance that reads the user's config.

## Goals / Non-Goals

**Goals:**
- No custom daemon. Assemble the whole thing from systemd units, PAM, and nixpkgs packages.
- Start a session only when someone connects, and keep it running until the user logs out.
- Reuse the user's existing niri config (keybinds, DMS, theming) unchanged, apart from the environment-import guard.

**Non-Goals:**
- Attaching to or mirroring a session already on the host's display.
- Audio, clipboard sync beyond what VNC provides, client-driven resize, multi-monitor sessions.
- Discovery or routing across the fleet. The client names the host.

## Decisions

### D1: VNC via wayvnc, attached to niri

wayvnc talks to niri directly over screencopy and virtual pointer/keyboard, so the portal's missing RemoteDesktop doesn't matter. It supports VeNCrypt/TLS with PAM, and it can listen on a Unix socket (`--unix-socket`).

Alternatives considered:
- **gnome-remote-desktop**: needs `Mutter.RemoteDesktop` (niri doesn't have it), and its headless multi-user mode needs GDM and gnome-shell.
- **xrdp**: X11 sessions only, so users wouldn't get niri.
- **weston RDP backend as the host compositor**: good transport and real input focus, but weston's RDP backend doesn't authenticate users. We'd have to write the front door ourselves.
- **Sunshine/Moonlight**: built to stream the *physical* display (KMS capture). Its input goes through a uinput device, which the seat's active compositor picks up, not a nested per-user session. It also runs one instance per host. It's a fine future `game-streaming` capability, just the wrong tool for this one.
- **RustDesk**: its Wayland support goes through the portal RemoteDesktop path, so it dead-ends the same way.

### D2: Headless host is cage, with niri nested inside

The session runs `cage` with `WLR_BACKENDS=headless`, and cage runs niri as its single fullscreen client (winit backend). cage is a wlroots kiosk compositor: one app, fullscreen, nothing else, which is the minimal host we need. Output size comes from `wlr-randr` against cage at startup, using the configured resolution. wayvnc attaches to **niri's** Wayland socket, not cage's, so it captures niri's output and injects input into niri.

Rendering goes through the GPU render node when there is one, and falls back to Mesa llvmpipe (software) otherwise. Slow, but it works on any host.

Alternatives considered: niri's internal headless backend has no supported way to turn it on, so it isn't used. If task 1.1 finds a usable one, drop cage and run niri directly. `vkms` plus niri's TTY backend needs a seat-active session per user, which can't work for concurrent users. sway headless would also work as a host, but cage is smaller and single-purpose.

### D3: Lifecycle from systemd system units, PAM-backed, one set per user

For each user U with `remoteDesktop.port = P`:

```
cairn-rd-U.socket      (system)  ListenStream=P, BindToDevice=tailscale0, FreeBind=true
        │ connect
        ▼
cairn-rd-proxy-U.service (system)  systemd-socket-proxyd /run/cairn-rd/U/vnc.sock
        │ Requires/After
        ▼
cairn-rd-session-U.service (system)  User=U, PAMName=cairn-remote-desktop
        └─ cairn-rd-launch: cage (headless) → niri [--session?] → wayvnc -u /run/cairn-rd/U/vnc.sock
```

- With `PAMName=` and `pam_systemd` in the dedicated PAM service, the session becomes a real logind session. That's what gives it `XDG_RUNTIME_DIR`, `user@U.service`, and the right cgroup. Environment sets `XDG_SESSION_TYPE=wayland` and `XDG_SESSION_CLASS=user`. No lingering needed, and the user manager starts only on demand.
- The PAM service for the *session* does account and session management only, no `auth`, because the user authenticates to wayvnc instead (D4). It's a separate service name, so it doesn't change `login`'s policy.
- The session unit has `Restart=no`. When niri exits, cage exits and the unit stops, which ends the logind session (spec: Logout ends the session). Reconnects hit a running proxy and session (spec: Session persists across disconnects).
- `systemd-socket-proxyd --exit-idle-time` stops the proxy when idle. The session isn't touched.
- Unit names use the username, so they're stable across hosts and readable in `systemctl`.

Alternatives considered: user-level socket units with linger. Rejected: lingering every user on every host starts all their `default.target` user services (syncthing, mcp-gateway, …) at boot whether or not anyone ever connects.

### D4: Authentication is wayvnc VeNCrypt (TLS) + PAM, enforced as owner-only

wayvnc runs as U with `enable_auth=true`, `enable_pam=true`, and a TLS cert and key. Clients use VeNCrypt X509Plain or TLSPlain, which TigerVNC and Remmina (libvncclient) both support. wayvnc checks credentials through PAM as an unprivileged process, and `unix_chkpwd` only verifies the calling user's own password, so only U can unlock U's session. The `remote-desktop` spec's Owner-only requirement relies on this, and task 1.2 checks it.

Each host gets a self-signed certificate, generated on first use by a oneshot unit into `/var/lib/cairn-remote-desktop/` (root-owned key, readable by a `cairn-remote-desktop` group the session units run with). Clients pin it on first connect. Tailscale already encrypts the transport, so TLS here mainly protects the password exchange.

Alternatives considered: `tailscale cert`. Rejected because it needs MagicDNS and HTTPS certs enabled on the tailnet, which is a tailnet-wide requirement a library shouldn't impose. RSA-AES (RA2) auth: client support is spottier than VeNCrypt.

### D5: Network exposure is BindToDevice plus interface-scoped firewall

Sockets use `BindToDevice=tailscale0` (`FreeBind=true` so boot order doesn't matter), and ports open via `networking.firewall.interfaces.tailscale0.allowedTCPPorts`. Belt and braces: either one alone is enough to keep LAN and WAN out. An assertion requires `services.tailscale.enable`. The interface name comes from `services.tailscale.interfaceName`.

### D6: Session role is decided at launch by who owns the Mutter names

`cairn-rd-launch` checks whether `org.gnome.Mutter.ScreenCast` already has an owner on U's user bus (`busctl --user status`):
- **Unowned (primary):** start niri with `--session`. It claims the portal-facing names and imports the environment, so portals and screencast follow the remote session.
- **Owned (isolated):** start niri without `--session` and export `CAIRN_SESSION_ISOLATED=1`. niri doesn't touch the bus names or the systemd/D-Bus environment, and the startup import is skipped (D7). Downside: D-Bus-activated apps and portal dialogs started *from* the remote session show up on the local display. This is documented, not fixed in v1.

If a local login happens later, while a primary remote session is running, the local `--session` niri takes the names back. That's acceptable and matches what logging in locally means.

Alternatives considered: refusing remote login while a local session exists. Too restrictive for the common case of reaching your own desktop while it sits locked at home. A private D-Bus per remote session: loses the keyring, secrets, and every user-bus service, which is worse.

### D7: The environment import is wrapped, not duplicated

Both profiles' `spawn-at-startup` entry for `dbus-update-activation-environment --systemd --all` becomes a small cairn script, `cairn-import-session-env`, that exits 0 when `CAIRN_SESSION_ISOLATED=1` and otherwise does the import. One niri config serves local, primary-remote, and isolated-remote sessions, and nothing forks the user's config.

### D8: Ports are declared per user, uniqueness is asserted per host

`cairn.users.users.<name>.remoteDesktop.port` lives in the user file, which every host shares, so a user's port is the same across the fleet without central allocation. Deriving ports from UIDs was rejected: UIDs are assigned per host and depend on order. The `remote-desktop` module asserts uniqueness among the host's users. `cairn-remote` gets a build-time map of user → port for every user on the client host.

### D9: Client is Remmina, wrapped by `cairn-remote`

Remmina is GTK3 and runs natively on Wayland. When it grabs the keyboard, niri honours keyboard-shortcuts-inhibit, so `Mod` combos reach the remote niri instead of the local one. TigerVNC's viewer goes through XWayland and can't inhibit. `cairn-remote` builds a `vnc://user@host:port` URI and runs `remmina -c`.

## Risks / Trade-offs

- [Nested niri under cage misbehaves: input focus, output sizing, frame pacing] → Task 1.1 is a spike that proves the stack by hand before any module code. Fallback host is sway headless. If niri's headless backend is reachable, drop the host compositor entirely.
- [Unauthenticated tailnet connections start a session (spawning happens before VNC auth)] → Accepted for v1. Only reachable from the tailnet, the session grants nothing without the owner's password, and it costs one idle session. Revisit with an idle-unauthenticated timeout if it ever matters.
- [`unix_chkpwd` behaviour differs (for example a PAM stack that doesn't use `pam_unix`), breaking owner-only auth] → Task 1.2 checks it explicitly. If it fails, the launcher passes wayvnc a PAM service whose stack adds `pam_succeed_if user = U`.
- [Users without a local password (key-only SSH, autologin) can't authenticate] → Documented. Remote desktop needs a password for each user.
- [Software rendering on GPU-less hosts is slow] → Accepted. Over-the-tailnet VNC at 1080p is usable with llvmpipe for desktop work.
- [Isolated sessions send portal UI to the local display] → Documented limitation (D6). Most remote use (monitorless mini, an unattended desktop) gets a primary session anyway.
- [Super/Mod captured by the client's own compositor] → Remmina's keyboard grab plus niri's shortcuts-inhibit (D9). Verified in task 4.2.

## Migration Plan

Purely additive and opt-in per host. Rollout: enable on mini first (monitorless, which is the main use case), then on desktop hosts. Rollback: drop `modules.remoteDesktop`. The per-user `remoteDesktop.port` declarations are harmless while unused.

## Open Questions

- The exact cage/wayvnc startup ordering (how the launcher waits for niri's socket) is an implementation detail for task 2.x.
- The proxy's idle-exit duration (a small fixed default is fine).
