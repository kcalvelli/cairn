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

### D1: VNC via wayvnc, attached to cage (not niri)

wayvnc speaks wlroots protocols (screencopy, virtual pointer and keyboard), so the portal's missing RemoteDesktop doesn't matter. It supports VeNCrypt/TLS with PAM, and it can listen on a Unix socket (`-u`).

**Spike finding (task 1.1):** wayvnc must attach to the **host compositor (cage)**, not to niri. niri's virtual-keyboard handling (from smithay) sends keys straight to the focused client and skips the compositor's bind handling. Attached to niri, typing works but no niri keybind ever fires. Attached to cage, the virtual keyboard goes through the wlroots seat, cage delivers ordinary `wl_keyboard` events to niri's winit window, and every bind works. Capture is the same either way: cage's output is niri's window, fullscreen.

Alternatives considered:
- **gnome-remote-desktop**: needs `Mutter.RemoteDesktop` (niri doesn't have it), and its headless multi-user mode needs GDM and gnome-shell.
- **xrdp**: X11 sessions only, so users wouldn't get niri.
- **weston RDP backend as the host compositor**: good transport and real input focus, but weston's RDP backend doesn't authenticate users. We'd have to write the front door ourselves.
- **Sunshine/Moonlight**: built to stream the *physical* display (KMS capture). Its input goes through a uinput device, which the seat's active compositor picks up, not a nested per-user session. It also runs one instance per host. It's a fine future `game-streaming` capability, just the wrong tool for this one.
- **RustDesk**: its Wayland support goes through the portal RemoteDesktop path, so it dead-ends the same way.

### D2: Headless host is cage, with niri nested inside

The session runs `cage -d` with `WLR_BACKENDS=headless`. cage's single client is a small session script that:
1. sets the headless output mode with `wlr-randr --output HEADLESS-1 --custom-mode <resolution>`,
2. starts wayvnc against cage's socket (D1),
3. runs `niri -c <session config>` in the foreground (winit backend, since `WAYLAND_DISPLAY` points at cage).

When niri exits, the script stops wayvnc, cage exits, and the unit stops.

**Spike findings (task 1.1, edge, niri 26.04, cage 0.3.1, wayvnc 0.10.2, RX 6750 XT):**
- `cage -d` is required. Without it, niri's winit window draws client-side decorations and the session is 1912x1048 inside a 1920x1080 output, with a black strip at the bottom. With it, the session is exactly the configured size.
- A nested niri uses **Alt** as `Mod`. The session config therefore wraps the user's config: an `include` of `~/.config/niri/config.kdl` followed by `input { mod-key-nested "Super"; }`. Checked: all of the user's settings load through the include, and Super binds work while Alt no longer triggers them.
- The user's DMS starts from the user's own `spawn-at-startup`, and `dms ipc …` from inside the nested session reaches the **nested** DMS, not the local one. Two DMS instances for one user coexist.
- The GPU render node is picked up automatically (radeonsi). Full 1920x1080 raw frames arrive over the Unix socket in about 20 ms.
- cage ignores SIGTERM while its client is alive, so the unit relies on systemd's control-group kill (`KillMode=control-group`, the default), not on signalling cage.
- vncdotool can't receive frames from wayvnc (it hangs after ServerInit). Tests use a minimal raw RFB client instead.

Alternatives considered: niri has no runtime-selectable headless backend (none found in 26.04's CLI, env, or strings), so the host compositor stays. `vkms` plus niri's TTY backend needs a seat-active session per user, which can't work for concurrent users. sway headless would also work as a host, but cage is smaller and single-purpose.

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
        └─ cairn-rd-launch: cage -d (headless) ─┬─ wayvnc -u /run/cairn-rd/U/vnc.sock   (attached to cage)
                                                └─ niri -c <state>/niri.kdl [-- cairn-rd-session-ready]   (never --session)
```

- With `PAMName=` and `pam_systemd` in the dedicated PAM service, the session becomes a real logind session. That's what gives it `XDG_RUNTIME_DIR`, `user@U.service`, and the right cgroup. Environment sets `XDG_SESSION_TYPE=wayland` and `XDG_SESSION_CLASS=user`. No lingering needed, and the user manager starts only on demand.
- The PAM service for the *session* does account and session management only, no `auth`, because the user authenticates to wayvnc instead (D4). It's a separate service name, so it doesn't change `login`'s policy.
- The session unit has `Restart=no`. When niri exits, cage exits and the unit stops, which ends the logind session (spec: Logout ends the session). Reconnects hit a running proxy and session (spec: Session persists across disconnects).
- `systemd-socket-proxyd --exit-idle-time` stops the proxy when idle. The session isn't touched.
- Unit names use the username, so they're stable across hosts and readable in `systemctl`.

Alternatives considered: user-level socket units with linger. Rejected: lingering every user on every host starts all their `default.target` user services (syncthing, mcp-gateway, …) at boot whether or not anyone ever connects.

**Registration.** The module is a *core* module (always imported), and `modules.remoteDesktop` maps to `cairn.remoteDesktop.enable`. A flag-gated import would hide `cairn.remoteDesktop.client.enable`, and pangolin needs the client without serving anything.

**Primary sessions go through `niri-session`.** With `NIRI_CONFIG` pointing at the wrapper config, the remote niri runs as `niri.service`, `graphical-session.target` comes up, and kded6, portals and other session-bound user services start exactly as they would after a greeter login. Afterwards the launcher unsets `NIRI_CONFIG` from the user manager, so a later local login doesn't inherit the remote wrapper. The wrapper also lives in the persistent state dir, so even a stale value points at a valid file. Isolated sessions run `niri -c` directly inside the unit, through the user's login shell.

### D4: Authentication is wayvnc VeNCrypt (TLS) + PAM, with an explicit owner check

wayvnc runs as U with `enable_auth=true`, `enable_pam=true`, and a TLS cert and key. Clients use VeNCrypt X509Plain or TLSPlain, which TigerVNC and Remmina (libvncclient) both support.

wayvnc always opens the PAM service `wayvnc` (hardcoded in `src/pam_auth.c`), and every user's wayvnc shares that service. Owner-only is enforced **explicitly**, so it doesn't depend on `unix_chkpwd` internals:

```
auth requisite pam_exec.so quiet <check-owner>   # [ "$PAM_USER" = "$(id -un)" ]
auth ...       pam_unix.so                        # normal password check
account ...    pam_unix.so
```

`pam_exec` runs the check as the calling process, which is wayvnc running as U. So a login name other than U fails before any password is looked at, on every host, whatever the number of users. `unix_chkpwd` refusing to verify other users' passwords for an unprivileged caller is a second, independent layer.

**TLS keys are per user, not per host.** On first start, the session unit generates a self-signed cert and key in `StateDirectory=cairn-remote-desktop/U` (mode 0700, owned by U). One user can't read another user's key, so on a multi-user host user A can't impersonate the server to user B. The cert persists, so the client's pinned fingerprint stays stable. Tailscale already encrypts the transport, so TLS here mainly protects the password exchange.

Alternatives considered: one host-wide key readable by a shared group. Rejected for the impersonation reason above. `tailscale cert`: needs MagicDNS and HTTPS certs enabled on the tailnet, which a library shouldn't require. RSA-AES (RA2) auth: client support is spottier than VeNCrypt.

### D5: Network exposure is BindToDevice plus interface-scoped firewall

Sockets use `BindToDevice=tailscale0` (`FreeBind=true` so boot order doesn't matter), and ports open via `networking.firewall.interfaces.tailscale0.allowedTCPPorts`. Belt and braces: either one alone is enough to keep LAN and WAN out. An assertion requires `services.tailscale.enable`. The interface name comes from `services.tailscale.interfaceName`.

### D6: Session role is decided at launch; niri never runs with `--session` in a remote session

**Deployment finding (mini, first connect):** `niri --session` strips `WAYLAND_DISPLAY` ("running as a session but WAYLAND_DISPLAY is set, removing it") and falls back to the TTY backend. A nested niri can never be a `--session` niri. The first design (primary sessions via `niri-session`/`niri.service`) started a real TTY session on mini's GPU instead of nesting in cage. It also ran `systemctl --user import-environment` with the launcher's whole environment, leaking `WLR_*`, `RD_*` and `NIRI_CONFIG` into the user manager.

So both roles run plain `niri -c <wrapper>` inside the session unit, and the role only decides what plumbing gets added:

- **Primary** (the user has no active `graphical-session.target` and nobody owns `org.gnome.Mutter.ScreenCast`): niri is started with a startup hook (`niri … -- cairn-rd-session-ready`). Running with niri's own environment, the hook imports only `WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_*` into systemd and D-Bus, records the display in the runtime dir, and starts `cairn-rd-graphical-session.service`. That's a cairn user unit which `BindsTo`/`Before` `graphical-session.target`, the job `niri.service` does for a local login. kded6, portals and other session-bound user services come up. Cleanup (after niri exits, and again from `ExecStopPost` for hard deaths) stops that unit, and unsets the imported variables only if `WAYLAND_DISPLAY` in the user manager is still *ours*, so a local login that happened meanwhile keeps its environment.
- **Isolated:** no hook, `CAIRN_SESSION_ISOLATED=1`, and the user manager is untouched. The trade-off: D-Bus-activated apps and portal dialogs started from the remote session show up on the local display. Documented, not fixed in v1.

niri's environment is scrubbed of cage and launcher variables (`env -u WLR_* -u RD_*`) before it starts, so nothing leaks into apps or, through the user's own `--all` import, into the user manager.

**Lost with `--session`:** niri only claims the `org.gnome.Mutter.*` names under `--session`, so `xdg-desktop-portal-gnome` can't screencast a remote session. That's a spec'd limit. File chooser and the other portals don't need those names.

Alternatives considered: refusing remote login while a local session exists, which is too restrictive for the common case of reaching your own desktop while it sits locked at home. A private D-Bus per remote session, which loses the keyring, secrets and every user-bus service.

**Deployment finding 2:** `PAMName=` plus `pam_systemd` moves the unit's processes into the logind session scope, so the service cgroup is empty. `Type=notify` can never work (systemd drops sd_notify from outside the unit), and `KillMode=control-group` has nothing to kill. The session unit is `Type=simple` with `TimeoutStopSec=10s` (cage ignores SIGTERM, so it gets SIGKILLed, and niri and wayvnc die with their compositor). The proxy's `ExecStartPre` waits for wayvnc's socket instead.

**Deployment finding 3:** the same move means *stopping the unit doesn't stop the session*. On mini, every SIGKILLed cage left its nested niri, DMS and ghostty running in an abandoned session scope (seven of them). The launcher records `$XDG_SESSION_ID`, and a root `ExecStopPost` (`cairn-rd-session-reap`) runs `loginctl terminate-session` on it, then `systemctl stop session-<id>.scope`. The second step is the one that counts: once the leader (cage) dies, logind marks the scope *abandoned*, and `terminate-session` silently does nothing, which was verified on mini. That kills the whole scope on any exit, clean logout included, so nothing the user launched outlives the session.

### D7: The environment import is wrapped, not duplicated

Both profiles' `spawn-at-startup` entry for `dbus-update-activation-environment --systemd --all` becomes a small cairn script, `cairn-import-session-env`, that exits 0 when `CAIRN_SESSION_ISOLATED=1` and otherwise does the import. One niri config serves local, primary-remote, and isolated-remote sessions, and nothing forks the user's config.

### D8: Ports are declared per user, uniqueness is asserted per host

`cairn.users.users.<name>.remoteDesktop.port` lives in the user file, which every host shares, so a user's port is the same across the fleet without central allocation. Deriving ports from UIDs was rejected: UIDs are assigned per host and depend on order. The `remote-desktop` module asserts uniqueness among the host's users. `cairn-remote` gets a build-time map of user → port for every user on the client host.

### D9: Client is Remmina, wrapped by `cairn-remote`

Remmina is GTK3 and runs natively on Wayland. When it grabs the keyboard, niri honours keyboard-shortcuts-inhibit, so `Mod` combos reach the remote niri instead of the local one. TigerVNC's viewer goes through XWayland and can't inhibit. `cairn-remote` builds a `vnc://user@host:port` URI and runs `remmina -c`.

## Risks / Trade-offs

- [Nested niri under cage misbehaves] → Settled by the task 1.1 spike: frames, sizing, pointer, keybinds and DMS all work (see D2). Remaining client-side risk is D9's keyboard grab.
- [Unauthenticated tailnet connections start a session (spawning happens before VNC auth)] → Accepted for v1. Only reachable from the tailnet, the session grants nothing without the owner's password, and it costs one idle session. Revisit with an idle-unauthenticated timeout if it ever matters.
- [A PAM misconfiguration lets user B unlock user A's session] → The explicit `pam_exec` owner check (D4) is the first `auth` rule, and gate task 7.1 proves it on mini (multiple users) before the end-to-end test.
- [Users without a local password (key-only SSH, autologin) can't authenticate] → Documented. Remote desktop needs a password for each user.
- [The login keyring stays locked in remote sessions] → `pam_gnome_keyring` is in the `wayvnc` auth stack (after the owner check), and it can unlock an already-running daemon at auth time. Best effort, checked in 7.4.
- [Software rendering on GPU-less hosts is slow] → Accepted. Over-the-tailnet VNC at 1080p is usable with llvmpipe for desktop work.
- [Isolated sessions send portal UI to the local display] → Documented limitation (D6). Most remote use (monitorless mini, an unattended desktop) gets a primary session anyway.
- [Super/Mod captured by the client's own compositor] → Remmina's keyboard grab plus niri's shortcuts-inhibit (D9). Verified in task 4.2.

## Migration Plan

Purely additive and opt-in per host. Rollout: enable on mini first (monitorless, which is the main use case), then on desktop hosts. Rollback: drop `modules.remoteDesktop`. The per-user `remoteDesktop.port` declarations are harmless while unused.

## Open Questions

- The exact cage/wayvnc startup ordering (how the launcher waits for niri's socket) is an implementation detail for task 2.x.
- The proxy's idle-exit duration (a small fixed default is fine).
