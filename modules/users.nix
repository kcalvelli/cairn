{
  inputs,
  self,
  config,
  lib,
  ...
}:
let
  cfg = config.cairn.users;

  # Per-user submodule type
  userSubmodule =
    { name, ... }:
    {
      options = {
        fullName = lib.mkOption {
          type = lib.types.str;
          description = "Full name of the user (used for system user description and git config).";
          example = "John Doe";
        };

        email = lib.mkOption {
          type = lib.types.str;
          default = "";
          description = "Email address (used for git config and other tools).";
          example = "user@example.com";
        };

        isAdmin = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Whether this user has admin privileges.
            Admin users get the 'wheel' group (sudo access) and are added to nix.settings.trusted-users.
          '';
        };

        homeProfile = lib.mkOption {
          type = lib.types.nullOr (
            lib.types.enum [
              "standard"
              "normie"
            ]
          );
          default = null;
          description = ''
            Home-manager profile for this user. When null, inherits the host's homeProfile.
            - standard: Full desktop with development tools and keyboard-driven workflow
            - normie: ChromeOS-like mouse-driven desktop with window controls and minimal keybindings
          '';
        };

        linger = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Enable lingering for this user. When true, the user's systemd
            user manager starts at boot and persists after logout, allowing
            user services to run without an active login session.
          '';
        };

        remoteDesktop.port = lib.mkOption {
          type = lib.types.nullOr lib.types.port;
          default = null;
          description = ''
            TCP port for this user's remote desktop session (tailnet only).
            Declared once in the user file, so it is the same on every host
            that lists this user and has `modules.remoteDesktop = true`.
            Must be unique among the users of any one host. null means no
            remote desktop listener for this user.
          '';
          example = 5901;
        };

        extraGroups = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional groups for this user beyond the auto-assigned ones.";
          example = [
            "dialout"
            "i2c"
          ];
        };
      };
    };

  # Determine which groups to add based on enabled modules
  autoGroups = lib.lists.unique (
    lib.flatten [
      # Desktop environment groups
      (lib.optionals (config.desktop.enable or false) [
        "networkmanager"
        "video"
        "input"
        "audio"
        "lp"
        "scanner"
        "greeter"
      ])

      # Graphics-specific groups
      (lib.optionals (config.graphics.enable or false) [
        "video"
      ])

      # Virtualization groups
      (lib.optionals (config.virt.libvirt.enable or false) [
        "kvm"
        "libvirtd"
        "qemu-libvirtd"
      ])

      (lib.optionals (config.virt.containers.enable or false) [
        "podman"
      ])

      # Hardware-specific groups
      (lib.optionals
        ((config.hardware.desktop.enable or false) || (config.hardware.laptop.enable or false))
        [
          "plugdev"
        ]
      )

      # Development and admin groups
      (lib.optionals ((config.development.enable or false) || (config.services.enable or false)) [
        "adm"
        "disk"
      ])

      # Additional groups specified globally
      cfg.extraGroups
    ]
  );

  # Compute groups for a specific user
  groupsForUser =
    userDef:
    let
      baseGroups = if cfg.autoGroups then autoGroups else [ ];
      adminGroups = if userDef.isAdmin then [ "wheel" ] else [ ];
    in
    lib.lists.unique (adminGroups ++ baseGroups ++ userDef.extraGroups);

  # Get list of all defined usernames
  userNames = lib.attrNames cfg.users;

  # Get list of admin usernames
  adminNames = lib.filter (name: cfg.users.${name}.isAdmin) userNames;

  # Get the first admin user (used by greeter, etc.)
  firstAdmin = if adminNames != [ ] then lib.head adminNames else null;
in
{
  options.cairn.users = {
    users = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule userSubmodule);
      default = { };
      description = ''
        Per-user definitions. Each attribute key is a username, and the value
        configures that user's system account, groups, and home-manager profile.

        Example:
          cairn.users.users.keith = {
            fullName = "Keith";
            email = "keith@example.com";
            isAdmin = true;
          };
          cairn.users.users.traci = {
            fullName = "Traci";
            isAdmin = false;
            homeProfile = "normie";
          };
      '';
    };

    autoGroups = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Automatically add users to groups based on enabled cairn modules.

        Groups are added based on which modules are enabled:
        - wheel: Admin users only (isAdmin = true)
        - networkmanager, video, input, audio, lp, scanner, greeter: desktop module
        - kvm, libvirtd, qemu-libvirtd: virt.libvirt module
        - podman: virt.containers module
        - plugdev: hardware.desktop or hardware.laptop modules
        - adm, disk: development or services modules

        Set to false to disable automatic group management.
      '';
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = ''
        Additional groups to add to all users.
        These are added on top of module-determined groups.
      '';
      example = [
        "dialout"
        "i2c"
      ];
    };

    defaultExtraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      readOnly = true;
      default = if cfg.autoGroups then autoGroups else [ ];
      description = ''
        Computed list of groups based on enabled modules (excludes wheel).
        Read-only; use extraGroups to add additional groups.
      '';
    };

    firstAdminUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      readOnly = true;
      default = firstAdmin;
      description = ''
        The username of the first admin user, or null if none defined.
        Used by the greeter and other components that need a primary user reference.
      '';
    };
  };

  config = lib.mkMerge [
    # Configure home-manager for user configurations
    {
      home-manager = {
        extraSpecialArgs = {
          inherit inputs self;
        };
      };
    }

    # Create accounts and configure home-manager for each defined user
    (lib.mkIf (userNames != [ ]) {
      users.users = lib.mapAttrs (name: userDef: {
        isNormalUser = lib.mkDefault true;
        description = lib.mkDefault userDef.fullName;
        extraGroups = lib.mkDefault (groupsForUser userDef);
        linger = lib.mkDefault userDef.linger;
      }) cfg.users;

      home-manager.users = lib.mapAttrs (name: userDef: {
        # Email passed through to home-manager for git config
        cairn.user.email = lib.mkDefault userDef.email;
      }) cfg.users;

      # Trusted nix users = admin users only
      nix.settings.trusted-users = adminNames;

      # Create standard XDG user directories for all users
      systemd.tmpfiles.rules = lib.flatten (
        lib.mapAttrsToList (
          name: userDef:
          let
            homeDir = config.users.users.${name}.home;
            gid = toString config.users.users.${name}.group;
          in
          [
            "d ${homeDir}/Desktop 0755 ${name} ${gid} -"
            "d ${homeDir}/Documents 0755 ${name} ${gid} -"
            "d ${homeDir}/Downloads 0755 ${name} ${gid} -"
            "d ${homeDir}/Music 0755 ${name} ${gid} -"
            "d ${homeDir}/Pictures 0755 ${name} ${gid} -"
            "d ${homeDir}/Videos 0755 ${name} ${gid} -"
            "d ${homeDir}/Public 0755 ${name} ${gid} -"
            "d ${homeDir}/Templates 0755 ${name} ${gid} -"
          ]
        ) cfg.users
      );
    })
  ];
}
