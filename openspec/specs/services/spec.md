# Networking & Self-Hosted Services

## Purpose
Manages network connectivity and self-hosted application infrastructure using a declarative reverse proxy pattern.

## Components

### Tailscale
- **Protocol**: Mesh VPN with automatic HTTPS certificate provisioning.
- **Requirement**: `networking.tailscale.domain` must be set for self-hosted services.
- **Implementation**: `modules/networking/tailscale.nix`

### Caddy Route Registry
- **Pattern**: Route Registry Pattern. Services register routes via `selfHosted.caddy.routes.<name>`.
- **Logic**: Automatic sorting - path-specific routes (priority 100) are evaluated before catch-all (priority 1000).
- **Features**: Automatic HTTPS via Tailscale, custom `extraConfig` for reverse proxy blocks, and `handleConfig` for outer blocks.
- **Implementation**: `modules/services/caddy.nix`, `modules/services/default.nix`

### Immich (Photo Backup)
- **Features**: Subdomain support (`selfHosted.immich.subdomain`), custom media location, and GPU acceleration.
- **Acceleration**: Optional AMD/Nvidia/Intel GPU support for video transcoding.
- **Networking**: Uses **Tailscale Services** (`cairn-immich.<tailnet>.ts.net`) for secure, magic-dns addressed access.
- **PWA Strategy**: Uses `loopbackProxy` for unified HTTPS access (`https://cairn-immich.<tailnet>/`) on both server and client.
- **PostgreSQL Collation Auto-Refresh**: A `postgresql-collation-refresh` oneshot service runs at boot after PostgreSQL starts. It refreshes collation versions on all databases, preventing journal warnings after glibc updates. The command is idempotent and safe to run on every boot.
- **Implementation**: `modules/services/immich.nix`

### Local AI (llama-server)
- **Features**: OpenAI-compatible API via Tailscale Services (`cairn-llama.<tailnet>.ts.net`).
- **Implementation**: `modules/ai/default.nix`

### File Synchronization
- **Syncthing XDG Sync**: Peer-to-peer XDG directory sync via Tailscale. See `openspec/specs/syncthing-xdg-sync/spec.md`.
- **Samba**: Local network file sharing for media/documents.
- **Implementation**: `modules/syncthing/default.nix`, `modules/networking/samba.nix`

## Requirements

### Requirement: Caddy Route Registry

Self-hosted services SHALL register their reverse-proxy routes through the `selfHosted.caddy.routes.<name>` registry rather than hand-authored Caddyfile blocks. The module SHALL order routes so that path-specific routes take precedence over catch-all routes.

#### Scenario: Service registers a route

- **Given**: A service sets `selfHosted.caddy.routes.<name>` with a backend
- **When**: The NixOS configuration is evaluated
- **Then**: Caddy serves that route with automatic HTTPS via Tailscale
- **And**: No hand-written Caddyfile handle block is required for that service

#### Scenario: Path-specific and catch-all routes coexist

- **Given**: Two routes are registered on the same domain, one path-specific and one catch-all
- **When**: Caddy's configuration is generated
- **Then**: The path-specific route (priority 100) is evaluated before the catch-all route (priority 1000)

### Requirement: Tailscale Domain Prerequisite

Self-hosted services SHALL require `networking.tailscale.domain` to be set, since routing and certificate provisioning depend on the tailnet domain.

#### Scenario: Domain configured

- **Given**: `networking.tailscale.domain` is set
- **When**: A self-hosted service is enabled
- **Then**: The service is reachable at its `<name>.<tailnet>.ts.net` address with a valid certificate

### Requirement: Immich Photo Backup

The Immich service SHALL be exposed over Tailscale Services with unified HTTPS access via the loopback proxy, and SHALL keep PostgreSQL collation metadata current across glibc updates.

#### Scenario: Immich enabled

- **Given**: `selfHosted.immich` is enabled
- **When**: The system is built
- **Then**: Immich is reachable at `https://cairn-immich.<tailnet>/` on both server and client via the loopback proxy
- **And**: An optional GPU acceleration path is available for video transcoding when configured

#### Scenario: PostgreSQL collation refresh at boot

- **Given**: Immich's PostgreSQL database is running
- **When**: The system boots
- **Then**: The `postgresql-collation-refresh` oneshot runs after PostgreSQL starts
- **And**: Collation versions on all databases are refreshed idempotently
- **And**: Post-glibc-update collation warnings do not appear in the journal

## Constraints
- **Registry Mandate**: All self-hosted services MUST use the registry pattern, NEVER hardcoded Caddyfile handle blocks.
- **Domain Consistency**: Services sharing a domain must be careful with path-based priorities.
