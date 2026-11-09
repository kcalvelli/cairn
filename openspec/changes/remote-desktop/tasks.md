# Tasks

## 1. Spike: prove the stack by hand (no module code)

- [ ] 1.1 On edge, from a TTY or nested test: run `WLR_BACKENDS=headless cage -- niri` with `CAIRN_SESSION_ISOLATED=1`, set the cage output to 1920x1080 with `wlr-randr`, attach `wayvnc` to niri's socket, and connect with Remmina. Verify that DMS renders, `Mod` keybinds reach the remote niri with Remmina's keyboard grab, and pointer and keyboard input land in niri windows. Also check whether niri has a runtime-selectable headless backend. Record the findings and the exact working command lines in `design.md` D2 (switch to sway headless or direct niri if cage fails).
- [ ] 1.2 Confirm owner-only PAM auth: run wayvnc as user A with `enable_pam=true` and TLS, and try logging in with user B's valid credentials. Verify that B is rejected and A is accepted. If B is accepted, apply the `pam_succeed_if` fallback from the Risks section and re-verify.
- [ ] 1.3 Confirm `systemd-run -p User=<u> -p PAMName=<svc> …` (no auth in the stack) produces a logind session with `XDG_RUNTIME_DIR` and `user@<uid>.service` running. Verify with `loginctl list-sessions` and `loginctl show-session`.

## 2. Session isolation in the desktop profiles

- [ ] 2.1 Add a `cairn-import-session-env` script that skips the import when `CAIRN_SESSION_ISOLATED=1`, and use it in place of the raw `dbus-update-activation-environment` spawn in `home/desktop/niri.nix` and `home/desktop/normie.nix`. Verify: `nix build` of example-config succeeds, a normal local login still sees `WAYLAND_DISPLAY` in `systemctl --user show-environment`, and running the script with the variable set leaves the environment unchanged.

## 3. Per-user port option

- [ ] 3.1 Add `remoteDesktop.port` (nullable port, default null) to the `cairn.users.users.<name>` submodule in `modules/users.nix`. Verify: example-config evaluates with and without the option set.
- [ ] 3.2 Document the option in `docs/USER_MODULE.md` and the `multi-user` spec's component list. Verify the documented snippet evaluates in example-config.

## 4. Remote desktop module

- [ ] 4.1 Create `modules/remote-desktop/default.nix` with options `cairn.remoteDesktop.{resolution, client.enable}` and assertions (Tailscale enabled, unique per-host ports, naming the clashing users). Register it in `modules/default.nix` and as a flagged module (`modules.remoteDesktop or false`) in `lib/default.nix`. Verify: one eval with Tailscale disabled and one with duplicate ports, each failing with the expected message.
- [ ] 4.2 Add the per-host TLS cert oneshot (`/var/lib/cairn-remote-desktop/`, root-owned key, group-readable by `cairn-remote-desktop`), the `cairn-remote-desktop` PAM service (account and session only, with `pam_systemd`), and the `cairn-rd-launch` script (role detection per D6, cage, then niri, then wayvnc on `/run/cairn-rd/<user>/vnc.sock`). Verify: the cert exists after first start, and `bash -n` passes on the launcher.
- [ ] 4.3 Generate a `cairn-rd-<user>.socket`, `cairn-rd-proxy-<user>.service` and `cairn-rd-session-<user>.service` for each user with a port, plus firewall openings on the Tailscale interface only. Verify: `nix eval` of the host shows the units for users with ports and none for users without, and that `networking.firewall.allowedTCPPorts` doesn't contain the ports.
- [ ] 4.4 Write `docs/REMOTE_DESKTOP.md`: enabling it, declaring ports, the client, the session roles, and the known limits (no audio, fixed resolution, isolated-session portals, password required). Link it from `docs/MODULE_REFERENCE.md`. Verify the enabling snippet evaluates in example-config.

## 5. Client

- [ ] 5.1 When `cairn.remoteDesktop.client.enable` is set, install Remmina and a `cairn-remote` script with a build-time user → port map. Handle `--user` and `--port`, and exit non-zero with a hint when the port is unknown. Verify: the script runs with `--user nosuchuser` and prints the hint, and with a known user it prints and launches the expected `vnc://` URI.
- [ ] 5.2 Make the client option default to on for hosts with the desktop module enabled, and off otherwise. Verify with `nix eval` on a desktop host and on a server example.

## 6. Init script

- [ ] 6.1 Add "Remote desktop (tailnet-only)" to the module picker in `scripts/init-config.sh` and to `remoteDesktop = {{ENABLE_REMOTE_DESKTOP}};` in `scripts/templates/host.nix.template` and `ai-install-prompt.md.template`, with a note that it needs Tailscale. Verify: `nix run .#init` in a temp dir with the option selected produces a host file containing `remoteDesktop = true;`.

## 7. Fleet integration

- [ ] 7.1 Run `nix fmt .` and `nix flake check --all-systems`, and verify both pass.
- [ ] 7.2 Deploy to mini (monitorless) with ports declared for two users. Verify the remote-desktop spec scenarios end to end: connecting from pangolin over Tailscale gives a fresh session, the LAN IP refuses the connection, another user's credentials are rejected, reconnecting reattaches, logging out ends the logind session, and the session is primary (the portal file chooser opens in the remote session).
- [ ] 7.3 Deploy to edge and connect as a user who is logged in locally. Verify the remote session is isolated: the local display is untouched, and an app D-Bus-activated locally still opens locally.

## Workflow follow-up

- Run `/opsx:verify`, then `/opsx:archive` once 7.x passes on real hardware.
