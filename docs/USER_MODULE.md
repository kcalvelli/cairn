# User Module Guide

## Overview

Cairn provides a multi-user system through the `cairn.users.users.<name>` submodule. Users are defined in per-user files and referenced by name from host configurations.

## Quick Start

### 1. Define a user

Create `users/alice.nix` in your configuration repository:

```nix
{ ... }:
{
  cairn.users.users.alice = {
    fullName = "Alice Smith";
    email = "alice@example.com";
    isAdmin = true;
  };
}
```

### 2. Reference from host config

In `hosts/myhost.nix`:

```nix
{ lib, ... }:
{
  hostConfig = {
    # ... other config ...
    users = [ "alice" ];  # Resolves users/alice.nix via configDir
  };
}
```

### 3. Set configDir in flake.nix

```nix
mkHost = hostname: cairn.lib.mkSystem (
  (import ./hosts/${hostname}.nix { lib = nixpkgs.lib; }).hostConfig // {
    configDir = self.outPath;  # Required: tells Cairn where users/ directory is
  }
);
```

That's it! Cairn automatically creates the user account, assigns groups, configures home-manager, and sets up git.

## User Options Reference

### `cairn.users.users.<name>`

Each attribute key is a username. Available options per user:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `fullName` | string | *required* | Full name (used for system description and git config) |
| `email` | string | `""` | Email address (used for git config) |
| `isAdmin` | bool | `false` | Admin privileges (wheel group + nix trusted-users) |
| `homeProfile` | null or enum | `null` | Per-user home profile override (`"standard"`, `"normie"`) |
| `extraGroups` | list of strings | `[]` | Additional groups beyond auto-assigned ones |
| `linger` | bool | `false` | Start the user's systemd manager at boot and keep it after logout |
| `remoteDesktop.port` | null or port | `null` | Tailnet-only remote desktop port for this user, the same on every host. Unique per host. See [REMOTE_DESKTOP.md](REMOTE_DESKTOP.md) |

When `homeProfile` is `null`, the user inherits the host's `homeProfile` setting.

### Multi-user example

```nix
# users/alice.nix
{ ... }:
{
  cairn.users.users.alice = {
    fullName = "Alice Smith";
    email = "alice@example.com";
    isAdmin = true;
    # homeProfile defaults to null (inherits host's homeProfile)
  };
}

# users/bob.nix
{ ... }:
{
  cairn.users.users.bob = {
    fullName = "Bob Jones";
    isAdmin = false;
    homeProfile = "normie";  # Override: Bob gets normie profile regardless of host
    extraGroups = [ "dialout" ];  # Bob needs serial port access
  };
}

# hosts/myhost.nix
{ lib, ... }:
{
  hostConfig = {
    # ...
    homeProfile = "standard";  # Default for users without explicit homeProfile
    users = [ "alice" "bob" ];    # Both users on this host
  };
}
```

Result: Alice gets `workstation` profile (inherited), Bob gets `minimal` profile (explicit override).

## What Cairn Automatically Provides

### 1. Group Membership (`cairn.users.autoGroups`)

**Default:** `true`

Groups are automatically assigned based on enabled modules:

| Group | When Added | Purpose |
|-------|------------|---------|
| `wheel` | `isAdmin = true` | sudo access |
| `networkmanager` | `desktop.enable` | Network management |
| `video` | `desktop.enable` or `graphics.enable` | GPU/graphics access |
| `input` | `desktop.enable` | Input device access |
| `audio` | `desktop.enable` | Audio device access |
| `lp` | `desktop.enable` | Printer access |
| `scanner` | `desktop.enable` | Scanner access |
| `kvm` | `virt.libvirt.enable` | KVM virtualization |
| `libvirtd` | `virt.libvirt.enable` | Libvirt VM management |
| `qemu-libvirtd` | `virt.libvirt.enable` | QEMU with libvirt |
| `podman` | `virt.containers.enable` | Container management |
| `plugdev` | `hardware.desktop/laptop.enable` | Device access |
| `adm` | `development.enable` or `services.enable` | Log file access |
| `disk` | `development.enable` or `services.enable` | Disk management |

### 2. Nix Trusted Users

Admin users (`isAdmin = true`) are automatically added to `nix.settings.trusted-users`.

### 3. Home-Manager Defaults (`cairn.home.enableDefaults`)

**Default:** `true`

Automatically configured for all users:

- **`home.stateVersion`**: Set to "24.11" by default
- **`FLAKE_PATH`**: Environment variable pointing to `$HOME/.config/nixos`

### 4. XDG Directories

Standard XDG user directories are automatically created for all users:
`Desktop`, `Documents`, `Downloads`, `Music`, `Pictures`, `Videos`, `Public`, `Templates`

### 5. Git Configuration

Git `user.name` and `user.email` are automatically configured from `fullName` and `email`.

### 6. Samba User Shares (`networking.samba.enableUserShares`)

**Default:** `false` (opt-in)

When enabled, automatically creates shares for common directories (Music, Pictures, Videos, Documents).

## Global User Options

### `cairn.users.autoGroups`
- **Type:** bool
- **Default:** `true`
- **Description:** Automatically add groups based on enabled modules

### `cairn.users.extraGroups`
- **Type:** list of strings
- **Default:** `[]`
- **Description:** Additional groups to add to all users (on top of module-based groups)

## Advanced Configuration

### Disabling Automatic Groups

If you need full control over group membership:

```nix
# In host config extraConfig
cairn.users.autoGroups = false;
```

### Adding Extra Groups for All Users

```nix
# In host config extraConfig
cairn.users.extraGroups = [ "dialout" "i2c" ];
```

### Overriding Home-Manager Defaults

```nix
home-manager.users.alice = {
  # Disable cairn defaults
  cairn.home.enableDefaults = false;

  # Or override individual values
  home.stateVersion = lib.mkForce "23.11";
  home.sessionVariables.FLAKE_PATH = lib.mkForce "/custom/path";
};
```

## Home-Manager Options

### `cairn.home.enableDefaults`
- **Type:** bool
- **Default:** `true`
- **Description:** Enable cairn home-manager defaults

### `cairn.home.stateVersion`
- **Type:** string
- **Default:** `"24.11"`
- **Description:** Default home-manager state version

### `cairn.home.flakePath`
- **Type:** null or string
- **Default:** `"${HOME}/.config/nixos"`
- **Description:** Path to NixOS flake (sets FLAKE_PATH variable)

### `cairn.users.users.<name>.email`
- **Type:** string
- **Default:** `""`
- **Description:** User's email address - automatically used for git commits and other tools

## Troubleshooting

### Groups Not Applied

Check that the relevant module is enabled:

```nix
# To get libvirtd groups, you need:
modules.virt = true;
virt.libvirt.enable = true;
```

### Samba Shares Not Created

Ensure you've enabled the feature in your host config:

```nix
# In hosts/yourhost.nix extraConfig:
networking.samba.enableUserShares = true;
```

## See Also

- [LIBRARY_USAGE.md](LIBRARY_USAGE.md) - Using cairn as a library (mkSystem API)
- [ADDING_HOSTS.md](ADDING_HOSTS.md) - Adding new hosts
- [SECRETS_MODULE.md](SECRETS_MODULE.md) - Secrets management
