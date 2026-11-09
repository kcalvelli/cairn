# Imports the niri session's environment into systemd --user and the D-Bus
# activation environment, unless this session was started isolated.
#
# An isolated session is a second graphical session for a user who's already
# logged in somewhere else on the host (cairn remote desktop sets
# CAIRN_SESSION_ISOLATED=1). The user bus is per user, not per session, so
# importing here would retarget the *other* session's D-Bus-activated apps
# to this display. Don't.
{ pkgs }:
pkgs.writeShellScript "cairn-import-session-env" ''
  if [ "''${CAIRN_SESSION_ISOLATED:-0}" = 1 ]; then
    echo "cairn-import-session-env: isolated session, leaving the activation environment alone" >&2
    exit 0
  fi
  exec ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd --all
''
