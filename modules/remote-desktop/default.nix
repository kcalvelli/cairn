# Remote Desktop
#
# Fresh, per-user, headless niri sessions over VNC, reachable only on the
# tailnet. Nobody has to be logged in at the machine; the machine doesn't
# even need a monitor.
#
#   <port> on tailscale0 ─▶ cairn-rd-<user>.socket
#                              └▶ cairn-rd-proxy-<user>.service   (systemd-socket-proxyd)
#                                    └▶ cairn-rd-session-<user>.service  (User=<user>, PAM, logind)
#                                          cage -d (headless) ─┬─ wayvnc   (VeNCrypt + PAM)
#                                                              └─ niri     (nested, user's own config)
#
# wayvnc attaches to cage, not niri: niri's virtual keyboard bypasses its
# own keybinds, cage's doesn't. See openspec/changes/remote-desktop/design.md.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cairn.remoteDesktop;
  hostName = config.networking.hostName;
  tsIface = config.services.tailscale.interfaceName;

  rdUsers = lib.filterAttrs (_: u: u.remoteDesktop.port != null) config.cairn.users.users;
  allPorts = lib.mapAttrs (_: u: u.remoteDesktop.port) rdUsers;

  # port -> [ users ] for every port claimed more than once
  portClashes = lib.filterAttrs (_: us: lib.length us > 1) (
    lib.groupBy' (acc: name: acc ++ [ name ]) [ ] (name: toString allPorts.${name}) (
      lib.attrNames allPorts
    )
  );

  # PAM: the login name must be the user wayvnc runs as. pam_exec runs this
  # as the calling process, so user B can never unlock user A's session no
  # matter what the rest of the stack does.
  checkOwner = pkgs.writeShellScript "cairn-rd-check-owner" ''
    [ -n "$PAM_USER" ] && [ "$PAM_USER" = "$(${pkgs.coreutils}/bin/id -un)" ]
  '';

  # Primary sessions only, run by niri at startup with niri's own environment.
  # Does the part of `niri --session` we can't have (it strips WAYLAND_DISPLAY,
  # so it can't nest): point the user manager at this display and bring up
  # graphical-session.target so session-bound user services start.
  sessionReady = pkgs.writeShellScript "cairn-rd-session-ready" ''
    echo "''${WAYLAND_DISPLAY:-}" > "$RD_RUN/display"
    ${pkgs.dbus}/bin/dbus-update-activation-environment --systemd \
      WAYLAND_DISPLAY DISPLAY NIRI_SOCKET XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP
    ${pkgs.systemd}/bin/systemctl --user start cairn-rd-graphical-session.service
  '';

  # Undo sessionReady. Runs after niri exits and again from ExecStopPost, so a
  # session that dies hard still doesn't leave the user manager pointed at a
  # display that's gone. Only unsets what still points at *our* display: if a
  # local login took over meanwhile, its environment stays put.
  sessionCleanup = pkgs.writeShellScript "cairn-rd-session-cleanup" ''
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.gnugrep
        pkgs.systemd
      ]
    }
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
    run="''${RUNTIME_DIRECTORY:-''${RD_RUN:-}}"
    [ -n "$run" ] && [ -s "$run/display" ] || exit 0
    systemctl --user stop cairn-rd-graphical-session.service || true
    if systemctl --user show-environment | grep -qx "WAYLAND_DISPLAY=$(cat "$run/display")"; then
      # Still ours, so no local login took over: shut the graphical session
      # down for real. Dropping our hold isn't enough; xdg-desktop-portal keeps
      # the target "needed" (niri-session force-stops it for the same reason),
      # and a stale target would make the next remote session think someone
      # else is logged in.
      systemctl --user stop graphical-session.target || true
      # The user's own --all import (cairn-import-session-env) brings in the
      # session id and class too; those die with the session as well.
      systemctl --user unset-environment WAYLAND_DISPLAY DISPLAY NIRI_SOCKET \
        XDG_SESSION_TYPE XDG_SESSION_DESKTOP XDG_CURRENT_DESKTOP \
        XDG_SESSION_ID XDG_SESSION_CLASS RD_RUN || true
    fi
    rm -f "$run/display"
  '';

  # ExecStopPost, as root: end the logind session this unit opened. pam_systemd
  # put every process (cage, niri, DMS, whatever the user launched) in that
  # session's scope, not in the unit, so stopping the unit alone leaves a whole
  # desktop running with no display. Found the hard way on mini.
  sessionReap = pkgs.writeShellScript "cairn-rd-session-reap" ''
    run="''${RUNTIME_DIRECTORY:-}"
    [ -n "$run" ] && [ -s "$run/session-id" ] || exit 0
    id=$(${pkgs.coreutils}/bin/cat "$run/session-id")
    ${pkgs.systemd}/bin/loginctl terminate-session "$id" 2>/dev/null || true
    # terminate-session is a no-op once logind has marked the scope abandoned
    # (it does that the moment cage, the session leader, dies). Stopping the
    # scope unit kills what's in it regardless.
    ${pkgs.systemd}/bin/systemctl stop "session-$id.scope" 2>/dev/null || true
  '';

  # Runs as cage's only client. WAYLAND_DISPLAY is cage's socket here.
  #
  # Note pam_systemd moves this whole process tree out of the service's cgroup
  # into the logind session scope. So no sd_notify (systemd ignores it from
  # outside the unit), and no KillMode tricks; the proxy waits for the socket.
  sessionScript = pkgs.writeShellScript "cairn-rd-session" ''
    set -u
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.bashInteractive
        pkgs.wayvnc
        pkgs.wlr-randr
      ]
    }:$PATH

    wlr-randr --output HEADLESS-1 --custom-mode "$RD_RESOLUTION" \
      || echo "cairn-rd: couldn't set $RD_RESOLUTION, keeping cage's default" >&2

    wayvnc -C "$RD_RUN/wayvnc.cfg" -S "$RD_RUN/wayvncctl.sock" -u "$RD_RUN/vnc.sock" &
    vnc=$!

    for _ in $(seq 100); do
      [ -S "$RD_RUN/vnc.sock" ] && break
      sleep 0.1
    done
    if [ ! -S "$RD_RUN/vnc.sock" ]; then
      echo "cairn-rd: wayvnc never opened its socket. Nothing to serve." >&2
      kill "$vnc" 2>/dev/null
      exit 1
    fi

    # niri never runs with --session here: --session strips WAYLAND_DISPLAY and
    # grabs the real GPU instead of nesting. Primary sessions get the session
    # plumbing from sessionReady; isolated ones get none of it, on purpose.
    hook=()
    if [ "$RD_ROLE" = primary ]; then
      unset CAIRN_SESSION_ISOLATED
      hook=(-- ${sessionReady})
    else
      export CAIRN_SESSION_ISOLATED=1
    fi

    # A bash login shell for the NixOS/home-manager profile (PATH and friends),
    # and nothing cage- or launcher-specific in niri's environment, so none of
    # it leaks into apps or the user manager.
    bash -l -c 'exec "$@"' cairn-rd \
      env -u WLR_BACKENDS -u WLR_HEADLESS_OUTPUTS -u WLR_RENDERER \
        -u RD_RESOLUTION -u RD_NIRI_CONFIG -u RD_ROLE \
      ${config.programs.niri.package}/bin/niri -c "$RD_NIRI_CONFIG" "''${hook[@]}"

    [ "$RD_ROLE" = primary ] && ${sessionCleanup}
    kill "$vnc" 2>/dev/null
    wait "$vnc" 2>/dev/null
    exit 0
  '';

  # ExecStart of the session unit: runs as the target user, inside a logind
  # session opened by PAMName=.
  launchScript = pkgs.writeShellScript "cairn-rd-launch" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.openssl
        pkgs.systemd
        pkgs.cage
      ]
    }:$PATH

    state="$STATE_DIRECTORY"
    run="$RUNTIME_DIRECTORY"
    # For the reaper (ExecStopPost): this unit's logind session, from pam_systemd
    echo "''${XDG_SESSION_ID:?pam_systemd gave us no session}" > "$run/session-id"
    export XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

    # Per-user TLS identity. Generated once and kept, so clients that pinned
    # it don't scream on every connect. Other users can't read it.
    if [ ! -s "$state/tls_cert.pem" ] || [ ! -s "$state/tls_key.pem" ]; then
      umask 077
      openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 -nodes \
        -days 3650 -subj "/CN=${hostName}" -addext "subjectAltName=DNS:${hostName}" \
        -keyout "$state/tls_key.pem" -out "$state/tls_cert.pem" 2>/dev/null
      umask 022
    fi

    cat > "$run/wayvnc.cfg" <<EOF
    enable_auth=true
    enable_pam=true
    private_key_file=$state/tls_key.pem
    certificate_file=$state/tls_cert.pem
    EOF

    # The user's own niri config, plus the one thing a nested niri gets wrong:
    # it wants Alt as Mod. Lives in the state dir so it outlives the session.
    cat > "$state/niri.kdl" <<EOF
    include "$HOME/.config/niri/config.kdl"
    input {
        mod-key-nested "Super"
    }
    EOF

    # Primary unless this user already has a graphical session on this host:
    # a running graphical-session.target, or a niri --session holding the
    # portal-facing Mutter names.
    if systemctl --user -q is-active graphical-session.target \
      || busctl --user status org.gnome.Mutter.ScreenCast >/dev/null 2>&1; then
      role=isolated
    else
      role=primary
    fi
    echo "cairn-rd: starting $role session for $(id -un) at ${cfg.resolution}" >&2

    unset WAYLAND_DISPLAY DISPLAY WAYLAND_SOCKET NIRI_SOCKET
    export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1
    [ -e /dev/dri/renderD128 ] || export WLR_RENDERER=pixman
    export RD_RUN="$run" RD_ROLE="$role" RD_RESOLUTION="${cfg.resolution}" \
      RD_NIRI_CONFIG="$state/niri.kdl"

    # -d: no client-side decorations, or niri loses 8x32 px to a window frame
    exec cage -d -- ${sessionScript}
  '';

  mkUserUnits = name: port: {
    sockets."cairn-rd-${name}" = {
      description = "Remote desktop listener for ${name} (tailnet only)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = toString port;
        BindToDevice = tsIface;
        FreeBind = true;
        Service = "cairn-rd-proxy-${name}.service";
      };
    };

    services."cairn-rd-proxy-${name}" = {
      description = "Remote desktop proxy for ${name}";
      bindsTo = [ "cairn-rd-session-${name}.service" ];
      after = [ "cairn-rd-session-${name}.service" ];
      serviceConfig = {
        User = name;
        # The session can't sd_notify (see sessionScript), so wait for wayvnc here.
        ExecStartPre = pkgs.writeShellScript "cairn-rd-wait-${name}" ''
          for _ in $(${pkgs.coreutils}/bin/seq 400); do
            [ -S /run/cairn-rd/${name}/vnc.sock ] && exit 0
            ${pkgs.coreutils}/bin/sleep 0.1
          done
          echo "cairn-rd: ${name}'s session never came up; see cairn-rd-session-${name}.service" >&2
          exit 1
        '';
        TimeoutStartSec = "60s";
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=10min /run/cairn-rd/${name}/vnc.sock";
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    services."cairn-rd-session-${name}" = {
      description = "Remote desktop session for ${name}";
      # A rebuild must not kick someone out of their desktop (or spin up an
      # empty one nobody asked for). Changes apply on the next session.
      restartIfChanged = false;
      after = [
        "systemd-user-sessions.service"
        "tailscaled.service"
      ];
      environment = {
        # pam_systemd reads these to register the logind session
        XDG_SESSION_TYPE = "wayland";
        XDG_SESSION_CLASS = "user";
        XDG_SESSION_DESKTOP = "niri";
        XDG_CURRENT_DESKTOP = "niri";
      };
      serviceConfig = {
        Type = "simple";
        User = name;
        PAMName = "cairn-remote-desktop";
        WorkingDirectory = "~";
        StateDirectory = "cairn-remote-desktop/${name}";
        StateDirectoryMode = "0700";
        RuntimeDirectory = "cairn-rd/${name}";
        RuntimeDirectoryMode = "0700";
        ExecStart = launchScript;
        ExecStopPost = [
          "-${sessionCleanup}"
          # '+': root, so it can always end the session even if logind says no to the user
          "+${sessionReap}"
        ];
        Restart = "no";
        # cage shrugs off SIGTERM while its client lives; don't wait 90s for it
        TimeoutStopSec = "10s";
      };
    };
  };

  userUnits = lib.mapAttrsToList mkUserUnits allPorts;

  # "<user> <port>" per line: what this host serves. Clients only know the
  # users defined on *their* machine, so they ask the host. Not secret on a
  # tailnet: names and port numbers, nothing else.
  directoryFile = pkgs.writeText "cairn-remote-desktop-directory" (
    lib.concatStrings (lib.mapAttrsToList (n: p: "${n} ${toString p}\n") allPorts)
  );

  directoryUnits = {
    sockets.cairn-rd-directory = {
      description = "Remote desktop port directory (tailnet only)";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = toString cfg.directoryPort;
        BindToDevice = tsIface;
        FreeBind = true;
        Accept = true;
      };
    };
    services."cairn-rd-directory@" = {
      description = "Remote desktop port directory";
      serviceConfig = {
        ExecStart = "${pkgs.coreutils}/bin/cat ${directoryFile}";
        StandardInput = "socket";
        StandardOutput = "socket";
        DynamicUser = true;
        PrivateNetwork = false;
        ProtectSystem = "strict";
        RuntimeMaxSec = "5s";
      };
    };
  };

  # Client: user -> port, for every user this host knows about
  portTable = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (n: p: "    ${n}) echo ${toString p} ;;") allPorts
  );

  # Grabs the server's TLS certificate the way a VNC client would see it:
  # RFB handshake, VeNCrypt, X509Plain, then TLS without verification, and
  # bails before sending any credentials. The server just sees a client that
  # hung up.
  fetchCert = pkgs.writeText "cairn-remote-fetch-cert.py" ''
    import socket, ssl, struct, sys

    host, port, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    try:
        s = socket.create_connection((host, port), timeout=20)
    except OSError as e:
        sys.exit(f"{host}:{port}: {e.strerror or e}")

    def rx(n):
        b = b""
        while len(b) < n:
            c = s.recv(n - len(b))
            if not c:
                sys.exit(f"{host}:{port} hung up mid-handshake")
            b += c
        return b

    if not rx(12).startswith(b"RFB 003."):
        sys.exit(f"{host}:{port} isn't speaking VNC")
    s.sendall(b"RFB 003.008\n")
    types = list(rx(rx(1)[0]))
    if 19 not in types:
        sys.exit(f"{host}:{port} doesn't offer VeNCrypt (offers {types}); not a cairn remote desktop?")
    s.sendall(bytes([19]))
    rx(2)
    s.sendall(bytes([0, 2]))
    if rx(1)[0] != 0:
        sys.exit("server refused VeNCrypt 0.2")
    k = rx(1)[0]
    subtypes = struct.unpack(f">{k}I", rx(4 * k))
    if 262 not in subtypes:
        sys.exit(f"server doesn't offer X509Plain (offers {subtypes})")
    s.sendall(struct.pack(">I", 262))
    if rx(1)[0] != 1:
        sys.exit("server refused X509Plain")
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE  # we're fetching it to pin it, not trusting it yet
    t = ctx.wrap_socket(s, server_hostname=host)
    der = t.getpeercert(binary_form=True)
    t.close()
    with open(out, "w") as f:
        f.write(ssl.DER_cert_to_PEM_cert(der))
  '';

  cairnRemote = pkgs.writeShellScriptBin "cairn-remote" ''
    set -euo pipefail
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.openssl
        pkgs.diffutils
        pkgs.bash
      ]
    }:$PATH

    usage() {
      echo "usage: cairn-remote <host> [--user <name>] [--port <port>]" >&2
      echo "Opens a remote desktop session on <host> over the tailnet." >&2
      exit 2
    }
    port_for() {
      case "$1" in
    ${portTable}
        *) return 1 ;;
      esac
    }
    fingerprint() { openssl x509 -in "$1" -noout -fingerprint -sha256 | cut -d= -f2; }

    [ $# -ge 1 ] || usage
    host=$1; shift
    user=$(id -un)
    port=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --user) user=''${2:?--user needs a name}; shift 2 ;;
        --port) port=''${2:?--port needs a number}; shift 2 ;;
        -h|--help) usage ;;
        *) echo "cairn-remote: no idea what '$1' is" >&2; usage ;;
      esac
    done

    if [ -z "$port" ]; then
      # The host knows its own users; this machine only knows its own.
      port=$(timeout 5 bash -c 'cat < "/dev/tcp/$1/$2"' _ "$host" ${toString cfg.directoryPort} 2>/dev/null \
        | while read -r name p; do [ "$name" = "$user" ] && echo "$p"; done) || true
      if [ -z "$port" ]; then
        port=$(port_for "$user") || {
          echo "cairn-remote: $host has no remote desktop for '$user' (or isn't answering), and neither does this machine." >&2
          echo "If you know the port: cairn-remote $host --user $user --port <port>" >&2
          exit 1
        }
      fi
    fi

    data="''${XDG_DATA_HOME:-$HOME/.local/share}/cairn-remote"
    mkdir -p "$data/known" "$data/profiles"
    pin="$data/known/$host-$port.pem"
    seen=$(mktemp)
    trap 'rm -f "$seen"' EXIT

    # Trust on first use, then hold the server to it. The cert is per user per
    # host, so the pin is keyed on host and port.
    ${pkgs.python3}/bin/python3 -I ${fetchCert} "$host" "$port" "$seen" || {
      echo "cairn-remote: couldn't reach a remote desktop at $host:$port. On the tailnet? Host has modules.remoteDesktop?" >&2
      exit 1
    }
    if [ -s "$pin" ]; then
      if ! cmp -s <(openssl x509 -in "$pin" -outform DER) <(openssl x509 -in "$seen" -outform DER); then
        echo "cairn-remote: $host:$port is presenting a DIFFERENT certificate than last time." >&2
        echo "  pinned: $(fingerprint "$pin")" >&2
        echo "  now:    $(fingerprint "$seen")" >&2
        echo "If you know why (the host was reinstalled, its state wiped), delete $pin and try again." >&2
        echo "If you don't, don't." >&2
        exit 1
      fi
    else
      echo "cairn-remote: first connection to $host:$port. The server presents:" >&2
      openssl x509 -in "$seen" -noout -subject >&2
      echo "  SHA256 $(fingerprint "$seen")" >&2
      if [ -t 0 ]; then
        read -r -p "Trust it from now on? [y/N] " answer
        case "$answer" in
          y|Y|yes) ;;
          *) echo "cairn-remote: not trusted, not connecting." >&2; exit 1 ;;
        esac
      else
        echo "cairn-remote: run this once from a terminal to confirm the certificate." >&2
        exit 1
      fi
      cp "$seen" "$pin"
    fi

    # A profile with the pinned cert and username already filled in. Remmina
    # otherwise asks for both mid-handshake, and the server gives the whole
    # handshake 30 seconds.
    profile="$data/profiles/$user@$host-$port.remmina"
    cat > "$profile" <<EOF
    [remmina]
    name=$user@$host
    protocol=VNC
    server=$host:$port
    username=$user
    cacert=$pin
    keyboard_grab=1
    colordepth=32
    quality=9
    EOF

    echo "cairn-remote: $user@$host:$port" >&2
    if [ -n "''${CAIRN_REMOTE_DRY_RUN:-}" ]; then
      echo "$profile"
      exit 0
    fi
    exec ${pkgs.remmina}/bin/remmina -c "$profile"
  '';
in
{
  options.cairn.remoteDesktop = {
    enable = lib.mkEnableOption ''
      tailnet-only remote desktop: per-user, on-demand headless niri sessions
      over VNC. Normally set through `modules.remoteDesktop = true`
    '';

    resolution = lib.mkOption {
      type = lib.types.strMatching "[0-9]+x[0-9]+";
      default = "1920x1080";
      description = "Display size of remote sessions on this host, as WIDTHxHEIGHT.";
      example = "2560x1440";
    };

    directoryPort = lib.mkOption {
      type = lib.types.port;
      default = 5899;
      description = ''
        Tailnet-only port where a serving host lists its users and their remote
        desktop ports, so `cairn-remote <host> --user <name>` works from any
        machine. Clients use the same value to ask. 5899 because libvirt's VNC
        consoles start at 5900.
      '';
    };

    client.enable = lib.mkOption {
      type = lib.types.bool;
      default = config.desktop.enable or false;
      defaultText = lib.literalExpression "config.desktop.enable";
      description = ''
        Install the remote desktop client: Remmina plus `cairn-remote <host>
        [--user <name>] [--port <port>]`. On by default on desktop hosts.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.services.tailscale.enable;
          message = ''
            cairn.remoteDesktop is tailnet-only and needs Tailscale.
            Enable the networking module (it turns Tailscale on), or turn
            modules.remoteDesktop off for this host.
          '';
        }
        {
          assertion = portClashes == { };
          message = ''
            cairn.remoteDesktop: two users can't share a remote desktop port on one host.
            ${lib.concatStringsSep "\n" (
              lib.mapAttrsToList (port: us: "  port ${port}: ${lib.concatStringsSep ", " us}") portClashes
            )}
            Give each user a unique cairn.users.users.<name>.remoteDesktop.port.
          '';
        }
        {
          assertion = !(lib.elem cfg.directoryPort (lib.attrValues allPorts));
          message = "cairn.remoteDesktop.directoryPort (${toString cfg.directoryPort}) collides with a user's remoteDesktop.port.";
        }
        {
          assertion = config.programs.niri.enable or false;
          message = ''
            cairn.remoteDesktop serves niri sessions, but niri isn't enabled on
            this host. Enable the desktop module too.
          '';
        }
      ];

      # Headless rendering still needs Mesa (llvmpipe when there's no GPU).
      hardware.graphics.enable = lib.mkDefault true;

      security.pam.services = {
        # Session side: systemd's PAMName= only runs account + session, which is
        # what gets us a proper logind session and user@.service.
        cairn-remote-desktop = {
          startSession = true;
          setLoginUid = true;
        };

        # Auth side: wayvnc hardcodes the service name "wayvnc".
        wayvnc = {
          unixAuth = true;
          # Unlock the login keyring with the password the user just typed, the
          # way a local login does. Best effort: needs the daemon already up.
          enableGnomeKeyring = config.security.pam.services.login.enableGnomeKeyring or false;
          rules.auth.cairn-rd-owner = {
            # First auth rule, ahead of unix-early and gnome_keyring: a wrong-user
            # attempt is refused before its password reaches anything.
            order = 100;
            control = "requisite";
            modulePath = "${pkgs.pam}/lib/security/pam_exec.so";
            args = [
              "quiet"
              "${checkOwner}"
            ];
          };
        };
      };

      networking.firewall.interfaces.${tsIface}.allowedTCPPorts = lib.attrValues allPorts ++ [
        cfg.directoryPort
      ];

      systemd = lib.mkMerge (
        userUnits
        ++ [
          directoryUnits
          {
            # Holds graphical-session.target up for a primary remote session,
            # the job niri.service does for a local login. Started by sessionReady.
            user.services.cairn-rd-graphical-session = {
              description = "Remote desktop graphical session (cairn)";
              bindsTo = [ "graphical-session.target" ];
              before = [ "graphical-session.target" ];
              wants = [ "graphical-session-pre.target" ];
              after = [ "graphical-session-pre.target" ];
              serviceConfig = {
                Type = "oneshot";
                RemainAfterExit = true;
                ExecStart = "${pkgs.coreutils}/bin/true";
              };
            };
          }
        ]
      );
    })

    (lib.mkIf cfg.client.enable {
      environment.systemPackages = [
        pkgs.remmina
        cairnRemote
      ];
    })
  ];
}
