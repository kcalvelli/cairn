# remote-desktop Specification

## Purpose
Lets any cairn user open a fresh, headless niri desktop session on any cairn host over the tailnet, without anyone logged in at the machine, while keeping that access off every network except Tailscale.

## Requirements

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
When `cairn.remoteDesktop.client.enable` is true, the host SHALL provide a graphical VNC client and a `cairn-remote <host> [--user <name>] [--port <port>]` command. The command SHALL default to the invoking user, and SHALL resolve the port from the target host's directory first and the local user table second.

#### Scenario: Connect to own session
- **WHEN** user U runs `cairn-remote mini` on a client host
- **THEN** a VNC client opens a connection to `mini` on U's remote-desktop port as user U

#### Scenario: Connect as a user the client machine doesn't define
- **WHEN** a user on edge, which only defines keith, runs `cairn-remote mini --user libby`
- **THEN** the port comes from mini's directory, and the client asks for libby's password

#### Scenario: Unknown user port
- **WHEN** neither the host's directory nor the local table knows the user, and no `--port` is given
- **THEN** the command exits non-zero and says which flag to pass

### Requirement: Port directory
A serving host SHALL publish, on a tailnet-only port (`cairn.remoteDesktop.directoryPort`, default 5899), a plain-text list of each served user and their port, one `<user> <port>` per line. It MUST NOT contain anything else.

#### Scenario: Directory lists served users
- **WHEN** a tailnet client connects to the directory port of a host serving alice (5901) and bob (5902)
- **THEN** it receives `alice 5901` and `bob 5902` and the connection closes

### Requirement: Trust on first use for the server certificate
`cairn-remote` SHALL pin each host and port's certificate on first use after showing its SHA-256 fingerprint and getting explicit confirmation in a terminal. It SHALL refuse to connect if a later connection presents a different certificate, and it SHALL hand the pinned certificate and username to the VNC client so that only the password is prompted.

#### Scenario: First connection
- **WHEN** a user connects to a host and port for the first time from a terminal
- **THEN** the fingerprint is shown, and the certificate is pinned only after the user confirms

#### Scenario: First connection without a terminal
- **WHEN** the first connection is made without a terminal
- **THEN** the command shows the fingerprint, refuses, and says to run it once from a terminal

#### Scenario: Certificate changed
- **WHEN** a pinned host presents a different certificate
- **THEN** the command refuses, shows both fingerprints, and says how to re-pin deliberately

### Requirement: Any user, active session or not
A user SHALL be able to start a remote session whether or not they're logged in at the host. A user who is logged in locally SHALL get an isolated remote session alongside the local one.

#### Scenario: Traci is logged in at mini
- **WHEN** someone connects to traci's port on mini with traci's credentials while traci is logged in at mini's display
- **THEN** a separate isolated session for traci is presented, and traci's local session keeps running untouched
