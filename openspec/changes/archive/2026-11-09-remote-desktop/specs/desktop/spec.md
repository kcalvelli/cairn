# Spec Delta

## ADDED Requirements

### Requirement: Session environment import is suppressible
The niri session's startup import of its environment into the systemd user manager and D-Bus activation environment SHALL run in normal sessions and SHALL be skipped when the session is marked isolated. This applies to every home profile that performs the import, including normie.

#### Scenario: Normal login
- **WHEN** a user logs in to niri at the physical display
- **THEN** the session's environment (including `WAYLAND_DISPLAY` and `XDG_MENU_PREFIX`) is imported into the systemd user and D-Bus activation environment

#### Scenario: Isolated session
- **WHEN** niri starts in a session marked isolated
- **THEN** the systemd user and D-Bus activation environment are left unchanged
