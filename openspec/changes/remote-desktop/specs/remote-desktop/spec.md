# Spec Delta

## Purpose

Lets any cairn user open a fresh, headless niri desktop session on any cairn host over the tailnet, without anyone logged in at the machine, while keeping that access off every network except Tailscale.

## ADDED Requirements

### Requirement: Host opt-in via module flag
Remote desktop serving SHALL be enabled per host by `modules.remoteDesktop = true` in the host config. Hosts without the flag SHALL listen on no remote-desktop port and install no remote-desktop server components.

#### Scenario: Flag absent
- **WHEN** a host config does not set `modules.remoteDesktop`
- **THEN** the built system contains no remote-desktop sockets, services, or firewall openings

#### Scenario: Flag set
- **WHEN** a host config sets `modules.remoteDesktop = true`
- **THEN** every cairn user on that host who has a `remoteDesktop.port` gets a remote-desktop listener on that port

### Requirement: Tailscale is required
Enabling remote desktop on a host SHALL require Tailscale to be enabled on that host. Evaluation MUST fail with an explanatory message otherwise.

#### Scenario: Tailscale disabled
- **WHEN** `modules.remoteDesktop = true` and Tailscale is not enabled
- **THEN** evaluation fails with a message stating that remote desktop is tailnet-only and needs Tailscale

### Requirement: Tailnet-only exposure
Remote-desktop listeners SHALL accept connections only on the Tailscale interface. The firewall SHALL open remote-desktop ports on the Tailscale interface only and on no other interface.

#### Scenario: Connection from the tailnet
- **WHEN** a client on the tailnet connects to `<host>:<user port>`
- **THEN** the connection reaches the remote-desktop authentication step

#### Scenario: Connection from the LAN or WAN
- **WHEN** a client connects to the user's port on any non-Tailscale address of the host
- **THEN** the connection is refused or dropped and no session is started

### Requirement: Fresh headless session per user
A remote connection for a user SHALL get that user's own headless niri session, separate from any local session on the host. It SHALL work on hosts with no physical display and when nobody is logged in.

#### Scenario: Monitorless host, nobody logged in
- **WHEN** a user connects to a host with no monitor attached and no active sessions
- **THEN** a new niri desktop session for that user is presented to the client

#### Scenario: User also logged in locally
- **WHEN** a user connects remotely while logged in at the host's physical display
- **THEN** the remote client gets a separate session, and the local display is not mirrored, locked, or changed

### Requirement: Session is a real login session
A remote session SHALL run as the target user and be registered with logind as a user session, with the user's home, runtime directory, and user service manager available as in a local login.

#### Scenario: Session registered with logind
- **WHEN** a remote session is running for user U
- **THEN** `loginctl list-sessions` on the host shows a session owned by U for the remote desktop, and U's user services are available inside it

### Requirement: Owner-only authentication
A connection SHALL be encrypted and SHALL authenticate with the session owner's own credentials through the host's PAM stack. Credentials of any other user, including other valid users on the host, MUST be rejected.

#### Scenario: Correct owner credentials
- **WHEN** a client connects to user U's port and supplies U's username and password
- **THEN** the client is shown U's session

#### Scenario: Another user's valid credentials
- **WHEN** a client connects to user U's port with valid credentials for a different user V
- **THEN** authentication fails and no desktop is shown

#### Scenario: Wrong password
- **WHEN** a client supplies an incorrect password
- **THEN** authentication fails and no desktop is shown

### Requirement: Session persists across disconnects
A remote session SHALL keep running when the client disconnects, and the next authenticated connection SHALL reattach to it. The session SHALL end when the user logs out of niri inside it.

#### Scenario: Reconnect after disconnect
- **WHEN** a client disconnects and later reconnects to the same user's port
- **THEN** the same session is shown with its windows intact

#### Scenario: Logout ends the session
- **WHEN** the user quits niri inside the remote session
- **THEN** the session's processes stop, the logind session closes, and the next connection starts a fresh session

### Requirement: Session role does not disturb the local session
If the user has no other graphical session on the host, the remote session SHALL act as the primary session: the activation environment and portals target it, and the user's graphical-session services start. Otherwise it SHALL run isolated and MUST NOT change the activation environment of the user's existing session.

#### Scenario: Primary remote session
- **WHEN** a remote session starts and the user has no other graphical session on the host
- **THEN** the portal file chooser opens inside the remote session and the user's graphical-session.target is active

#### Scenario: Primary session cleans up after itself
- **WHEN** a primary remote session ends, cleanly or not
- **THEN** the user's systemd activation environment no longer points at the remote display, and graphical-session.target is no longer held by it

#### Scenario: Isolated remote session
- **WHEN** a remote session starts while the user has a local graphical session
- **THEN** apps D-Bus-activated from the local session still open on the local display

### Requirement: No screencast inside remote sessions
Remote sessions SHALL NOT offer portal screencast (screen sharing from apps inside the session). The documentation MUST state this limit.

#### Scenario: App requests screen sharing in a remote session
- **WHEN** an app inside a remote session asks the portal to share the screen
- **THEN** no remote-session screen is offered, and the limit is documented in REMOTE_DESKTOP.md

### Requirement: Configurable session resolution
The headless session's display resolution SHALL be configurable per host. It SHALL default to 1920x1080.

#### Scenario: Default resolution
- **WHEN** no resolution is configured
- **THEN** the remote session's output is 1920x1080

#### Scenario: Custom resolution
- **WHEN** the host sets the remote-desktop resolution to 2560x1440
- **THEN** the remote session's output is 2560x1440

### Requirement: Client launcher
When `cairn.remoteDesktop.client.enable` is true, the host SHALL provide a graphical VNC client and a `cairn-remote <host> [--user <name>] [--port <port>]` command. The command SHALL default to the invoking user and that user's declared port.

#### Scenario: Connect to own session
- **WHEN** user U runs `cairn-remote mini` on a client host
- **THEN** a VNC client opens a connection to `mini` on U's declared remote-desktop port as user U

#### Scenario: Connect as another user
- **WHEN** a user runs `cairn-remote edge --user libby`
- **THEN** the client connects to `edge` on libby's declared port and asks for libby's credentials

#### Scenario: Unknown user port
- **WHEN** `--user` names a user with no declared port and no `--port` is given
- **THEN** the command exits non-zero and says which flag to pass
