# Remote Desktop

Log in to any cairn host from anywhere on your tailnet and get your own fresh niri desktop. Nobody has to be at the machine, and it doesn't need a monitor. It isn't screen sharing: you get a separate session that runs your own niri config, with DMS, keybinds and theme.

Tailnet only. The listener binds to the Tailscale interface, and nothing on your LAN or the internet can reach it.

## Turn it on

**1. Give each user a port.** Do it once, in their user file. The port is the same on every host that user is on.

```nix
# users/alice.nix
{ ... }:
{
  cairn.users.users.alice = {
    fullName = "Alice Smith";
    remoteDesktop.port = 5901;
  };
}
```

```nix
# users/bob.nix
{ ... }:
{
  cairn.users.users.bob = {
    fullName = "Bob Smith";
    remoteDesktop.port = 5902;
  };
}
```

Ports must be unique among the users on a host, and evaluation fails if two users collide. Users without a port get no listener.

**2. Enable it on the hosts that should serve sessions.**

```nix
# hosts/mini.nix
hostConfig = {
  modules = {
    desktop = true;        # remote sessions are niri sessions
    networking = true;     # brings Tailscale, which is required
    remoteDesktop = true;
  };
  extraConfig = {
    cairn.remoteDesktop.resolution = "2560x1440";   # optional, default 1920x1080
  };
};
```

**3. Every user who'll log in remotely needs a password.** Authentication is your normal login password (via PAM). Key-only accounts can't get in.

## Connect

Desktop hosts get the client automatically (Remmina plus `cairn-remote`):

```bash
cairn-remote mini                  # you, on your own port
cairn-remote edge --user libby     # someone else's session (needs their password)
cairn-remote mini --port 5905      # a user this machine doesn't know about
```

Any VNC client that does VeNCrypt (TLS with username and password) works too: `vnc://<user>@<host>:<port>`. On first connect, the client shows a self-signed certificate. Accept it once, and it stays the same after that.

To turn the client on for a host that isn't a desktop, or off for one that is: `cairn.remoteDesktop.client.enable`.

## How a session behaves

- **It starts when you connect.** It's a real login session: your user services, keyring and `~` are all there.
- **It survives disconnects.** Close the client, reconnect later, and your windows are where you left them.
- **It ends when you log out of niri inside it.** The next connection starts fresh.
- **Only you can unlock your session.** Your port only accepts your own username and password. Another user's valid credentials are rejected before their password is even checked.
- **`Super` works as `Mod`, like at the machine.** Remmina's "grab keyboard" sends `Super` combos to the remote session instead of your local one.

### Primary and isolated sessions

Your D-Bus session (portals, the activation environment) is per user, not per session. So:

- **Nobody logged in as you on that host:** the remote session is **primary**. File pickers, app activation and your session services all target it. This is the normal case for a monitorless box.
- **You're also logged in at the machine:** the remote session is **isolated**. It leaves your local session alone, but anything that goes through your D-Bus session, such as portal file pickers, screen-share prompts and apps that run as a single shared instance (ghostty), shows up on the **local** screen. Launch things from inside the remote session when you can.

## Limits

- No audio.
- No screen sharing *from* apps inside a remote session (portal screencast needs niri's session mode, and a nested niri can't have it).
- Fixed resolution per host (`cairn.remoteDesktop.resolution`). The window doesn't follow the client's size.
- One display per session.
- Hosts without a GPU render in software (llvmpipe). It's fine for desktop work, but don't expect games.
- Keyring unlock in remote sessions is best effort.

## Troubleshooting

```bash
systemctl status cairn-rd-alice.socket            # is the listener up?
systemctl status cairn-rd-session-alice.service   # is the session running? which role?
journalctl -u cairn-rd-session-alice.service      # launcher, cage, niri, wayvnc output
journalctl -t wayvnc                              # authentication failures
loginctl list-sessions                            # the remote session shows up here
```

- **Connection refused:** you're probably not on the tailnet, or you connected to the host's LAN address. Use its tailnet name.
- **Authentication fails with the right password:** check that you're on *your* port. Alice's password doesn't work on Bob's port, by design.
- **Black screen, then disconnect:** read the session unit's journal. A broken niri config kills the session the same way it would a local login.
