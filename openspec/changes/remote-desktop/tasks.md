# Tasks

## 1. Spike: prove the stack by hand (no module code)

- [x] 1.1 On edge, from a TTY or nested test: run `WLR_BACKENDS=headless cage -- niri` with `CAIRN_SESSION_ISOLATED=1`, set the cage output to 1920x1080 with `wlr-randr`, attach `wayvnc` to niri's socket, and connect with Remmina. Verify that DMS renders, `Mod` keybinds reach the remote niri with Remmina's keyboard grab, and pointer and keyboard input land in niri windows. Also check whether niri has a runtime-selectable headless backend. Record the findings and the exact working command lines in `design.md` D2 (switch to sway headless or direct niri if cage fails).
- Tasks 1.2 and 1.3 (owner-only PAM, PAMName logind session) need root and a second user, and edge has neither. They moved to gate tasks 7.1 and 7.2, which run on mini (multiple users) after deployment and before the end-to-end checks.

## 2. Session isolation in the desktop profiles

- [x] 2.1 Add a `cairn-import-session-env` script that skips the import when `CAIRN_SESSION_ISOLATED=1`, and use it in place of the raw `dbus-update-activation-environment` spawn in `home/desktop/niri.nix` and `home/desktop/normie.nix`. Verify: `nix build` of example-config succeeds, a normal local login still sees `WAYLAND_DISPLAY` in `systemctl --user show-environment`, and running the script with the variable set leaves the environment unchanged.

## 3. Per-user port option

- [x] 3.1 Add `remoteDesktop.port` (nullable port, default null) to the `cairn.users.users.<name>` submodule in `modules/users.nix`. Verify: example-config evaluates with and without the option set.
- [x] 3.2 Document the option in `docs/USER_MODULE.md` (the `multi-user` main spec picks it up from the delta at archive). Verify the option row renders and that example-config evaluates with the option set.

## 4. Remote desktop module

- [x] 4.1 Create `modules/remote-desktop/default.nix` with options `cairn.remoteDesktop.{resolution, client.enable}` and assertions (Tailscale enabled, unique per-host ports, naming the clashing users). Register it in `modules/default.nix` and as a flagged module (`modules.remoteDesktop or false`) in `lib/default.nix`. Verify: one eval with Tailscale disabled and one with duplicate ports, each failing with the expected message.
- [x] 4.2 Add the per-host TLS cert oneshot (`/var/lib/cairn-remote-desktop/`, root-owned key, group-readable by `cairn-remote-desktop`), the `cairn-remote-desktop` PAM service (account and session only, with `pam_systemd`), and the `cairn-rd-launch` script (role detection per D6, cage, then niri, then wayvnc on `/run/cairn-rd/<user>/vnc.sock`). Verify: `bash -n` and shellcheck pass on the launcher and session scripts, the generated PAM stack puts the owner check first, and the owner check (same store path as the module's) accepts only the caller's own name. Cert-on-first-start is a runtime check, covered by 7.3.
- [x] 4.3 Generate a `cairn-rd-<user>.socket`, `cairn-rd-proxy-<user>.service` and `cairn-rd-session-<user>.service` for each user with a port, plus firewall openings on the Tailscale interface only. Verify: `nix eval` of the host shows the units for users with ports and none for users without, and that `networking.firewall.allowedTCPPorts` doesn't contain the ports.
- [x] 4.4 Write `docs/REMOTE_DESKTOP.md`: enabling it, declaring ports, the client, the session roles, and the known limits (no audio, fixed resolution, isolated-session portals, password required). Link it from `docs/MODULE_REFERENCE.md`. Verify the enabling snippet evaluates in example-config.

## 5. Client

- [x] 5.1 When `cairn.remoteDesktop.client.enable` is set, install Remmina and a `cairn-remote` script with a build-time user → port map. Handle `--user` and `--port`, and exit non-zero with a hint when the port is unknown. Verify: the script runs with `--user nosuchuser` and prints the hint, and with a known user it prints and launches the expected `vnc://` URI.
- [x] 5.2 Make the client option default to on for hosts with the desktop module enabled, and off otherwise. The module is a core module, so the client works on hosts that don't serve. Verify with `nix eval` on a desktop host and on a server example.

## 6. Init script

- [x] 6.1 Add "Remote desktop (tailnet-only)" to the module picker in `scripts/init-config.sh` and to `remoteDesktop = {{ENABLE_REMOTE_DESKTOP}};` in `scripts/templates/host.nix.template` and `ai-install-prompt.md.template`, with a note that it needs Tailscale. New user files get the next free config-wide port, starting at 5901. Verify: `nix run .#init` in a temp dir with the option selected produces a host file containing `remoteDesktop = true;`.

## 7. Fleet integration

- [x] 7.1 Run `nix fmt .` and `nix flake check --all-systems`, and verify both pass.
- [x] 7.2 GATE on mini (multiple users): owner-only auth. With users A and B both having ports, connect to A's port with B's valid credentials, then with a wrong password for A, then with the right password for A. Verify that only the last succeeds, and that `journalctl -t wayvnc`/`pam_exec` shows the owner-check rejection for B. **Result:** on mini, traci's name on keith's port is rejected by `pam_exec` in 0.1 s with no `pam_unix` or keyring call, a wrong password for keith is rejected by `pam_unix`, and keith's real password works. Because the owner check runs before any password is read, another user's *valid* password is rejected exactly like an invalid one.
- [x] 7.3 GATE on mini: logind integration. Also verify that after logout or a forced stop, no niri/DMS/cage processes remain and the session scope is gone (`loginctl list-sessions` shows nothing abandoned). Then connect as A and verify that `loginctl list-sessions` shows A's remote session (class user, type wayland), that `user@<uid(A)>.service` is running, and that logging out of niri closes the session. **Result:** sessions show in `loginctl` as class user, type wayland. `user@` and `graphical-session.target` come up for primary sessions. Logouts (keith session 27, traci) leave no scope, no processes, and a clean user environment.
- [x] 7.4 End to end on mini (monitorless): connecting from edge over Tailscale (edge has a local niri session, so this also proves the client-side keyboard grab under niri) gives a fresh session, the LAN IP refuses the connection, reconnecting reattaches, the session is primary (the portal file chooser opens in the remote session), and Remmina's keyboard grab delivers `Super` binds to the remote niri. **Result:** from edge (not pangolin): fresh session, LAN IP dropped, reconnect reattaches (session 29 survived a rebuild), primary role with portals, kded6 and keyring, and `Super` delivered through Remmina's grab. The file chooser wasn't opened explicitly; xdg-desktop-portal(-gnome) was running against the remote display.
- [x] 7.5 Deploy to edge and connect as a user who is logged in locally. Verify the remote session is isolated: the local display is untouched, and an app D-Bus-activated locally still opens locally. **Result:** run on mini instead (edge doesn't serve). Traci, logged in at mini's display, got an isolated remote session from edge, and her local session's processes were untouched.

## 8. Findings from the mini rollout

- [x] 8.1 Primary sessions don't use `niri --session` (it can't nest). They use a startup hook plus the `cairn-rd-graphical-session` holder. Verified on mini: session 27 came up primary with portals, kded6 and the keyring.
- [x] 8.2 Session processes live in the logind scope. The reaper stops the scope on any exit. Verified on mini: session 27's scope and environment were gone after the stop.
- [x] 8.3 Cleanup stops `graphical-session.target` and clears the session vars while they're still ours, and session units don't restart on switch. Verified on mini: session 29 survived the rebuild.
- [x] 8.4 `cairn-remote` pins the cert TOFU and hands Remmina a profile with it. Verified: all five TOFU cases against mini, and keith's Remmina login plus `Super` grab from edge.
- [x] 8.5 The owner check runs first in the live PAM stack. Verified on mini: traci's name on keith's port is rejected by `pam_exec` in 0.1 s with no `pam_unix` or keyring call.
- [x] 8.6 Port directory: deploy, then verify `cairn-remote mini --user traci` from edge resolves 5902 via mini's directory, and that traci (logged in locally on mini) gets an isolated session without disturbing her local one. **Result:** `cairn-remote mini --user traci` from edge resolved 5902 via mini's directory and pinned traci's own cert.

## 9. Follow-ups (not blocking)

- Keyring unlock in remote sessions wasn't verified (best effort by design).
- `pam_unix(wayvnc:account): setuid failed` on every successful login: wayvnc runs as the user, so pam_unix's account phase can't use its root-only helper. Logins work, but whether account and password expiry is enforced for remote logins is unverified.
- An unauthenticated connection still starts a session (accepted v1 risk, tailnet only).

## Workflow follow-up

- Run `/opsx:verify`, then `/opsx:archive` once 7.x passes on real hardware.
