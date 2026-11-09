# Spec Delta

## ADDED Requirements

### Requirement: Per-user remote desktop port
The `cairn.users.users.<name>` submodule SHALL provide a `remoteDesktop.port` option (port or null, default null). The port is declared in the user file, so it SHALL apply on every host that includes that user. A null port means the user has no remote-desktop listener.

#### Scenario: Port declared once, applies fleet-wide
- **WHEN** `users/alice.nix` sets `remoteDesktop.port = 5901` and hosts A and B both list `alice` with remote desktop enabled
- **THEN** alice's remote-desktop listener is on port 5901 on both A and B

#### Scenario: No port declared
- **WHEN** a user leaves `remoteDesktop.port` unset
- **THEN** no remote-desktop listener is created for that user on any host

### Requirement: Remote desktop ports are unique per host
Within one host, no two users SHALL declare the same remote-desktop port. Evaluation MUST fail if they do, naming the users and the port.

#### Scenario: Duplicate port
- **WHEN** users alice and bob on the same host both set `remoteDesktop.port = 5901`
- **THEN** evaluation fails with a message naming alice, bob, and 5901
