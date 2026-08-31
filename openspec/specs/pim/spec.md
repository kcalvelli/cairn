# Personal Information Management (PIM)

## Purpose

Provides AI-powered email management for Cairn desktop users through cairn-mail.

## Components

### Email: cairn-mail

**cairn-mail** is an AI-powered email management system designed for NixOS users.

#### Features
- **Multi-Account Support**: Gmail (OAuth2), IMAP/SMTP, Outlook (planned)
- **AI Classification**: LLM-powered tagging via OpenAI-compatible API with 35-tag default taxonomy
- **Privacy-First**: All data stored locally in SQLite; AI backend configurable (local or remote)
- **Modern UI**: Responsive web interface with PWA support, dark mode, keyboard shortcuts
- **Real-Time Sync**: WebSocket updates, systemd timer background sync
- **Declarative Config**: Email accounts and AI settings configured in Nix

#### Architecture
```
Web UI (React/Material-UI)
    ↓ HTTP/WebSocket
FastAPI Backend (Python)
    ↓
Email Providers (Gmail/IMAP) + OpenAI-compatible AI + SQLite
```

#### Implementation
- **NixOS Module**: `modules/pim/default.nix` (system services)
- **Home Module**: `home/pim/default.nix` (user configuration)
- **External Flake**: `inputs.cairn-mail`

### Calendar

Calendar functionality uses a layered approach (unchanged from previous architecture):

1. **Sync**: vdirsyncer for CalDAV synchronization
2. **CLI/Widget**: khal (bundled with DMS) for terminal access and shell widget
3. **GUI**: PWA apps (Google Calendar, Fastmail, etc.) for graphical interface

#### Implementation
- **Home Module**: `home/calendar/default.nix` (systemd services)
- **Manual Config**: `~/.config/vdirsyncer/config` (user must configure)

### Contacts

Contacts are managed through external services:

- **Cloud Providers**: Gmail, iCloud, Outlook (web UI)
- **Future**: cairn-mail contacts module (planned)

## Configuration

### NixOS Module Options

```nix
pim = {
  enable = lib.mkEnableOption "Personal Information Management (cairn-mail)";

  role = lib.mkOption {
    type = lib.types.enum [ "server" "client" ];
    default = "server";
    description = ''
      PIM deployment role:
      - "server": Run cairn-mail backend service (requires AI module)
                  Auto-registers as cairn-mail.<tailnet>.ts.net via Tailscale Services
      - "client": PWA desktop entry only (connects to cairn-mail.<tailnet>.ts.net)
    '';
  };

  # Server-only options (ignored when role = "client")
  port = lib.mkOption {
    type = lib.types.port;
    default = 8080;
    description = "Port for cairn-mail web UI (server role only)";
  };

  user = lib.mkOption {
    type = lib.types.str;
    description = "User to run cairn-mail service as (server role only)";
  };

  sync = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable background sync service (server role only)";
    };
    frequency = lib.mkOption {
      type = lib.types.str;
      default = "5m";
      description = "Sync frequency (systemd timer format)";
    };
  };

  # PWA options (both roles)
  pwa = {
    enable = lib.mkEnableOption "Generate cairn-mail PWA desktop entry";
    tailnetDomain = lib.mkOption {
      type = lib.types.str;
      example = "taile0fb4.ts.net";
      description = ''
        Tailscale tailnet domain for PWA URL generation.
        Required when pwa.enable = true.
        PWA points to: https://cairn-mail.<tailnetDomain>/
      '';
    };
  };
};
```

> **Note**: Client role requires a server with `networking.tailscale.authMode = "authkey"` running on the tailnet. The server must be deployed first to register the Tailscale Service `cairn-mail`.

### Home-Manager Module Options

```nix
programs.cairn-mail = {
  enable = lib.mkEnableOption "cairn-mail email client";

  accounts.<name> = {
    provider = lib.mkOption {
      type = lib.types.enum [ "gmail" "imap" "outlook" ];
    };
    email = lib.mkOption { type = lib.types.str; };
    realName = lib.mkOption { type = lib.types.str; };

    # OAuth accounts (Gmail/Outlook)
    oauthTokenFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Path to OAuth token (e.g., agenix secret)";
    };

    # IMAP/SMTP accounts
    passwordFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
    };
    imap = {
      host = lib.mkOption { type = lib.types.str; };
      port = lib.mkOption { type = lib.types.port; default = 993; };
      tls = lib.mkOption { type = lib.types.bool; default = true; };
    };
    smtp = {
      host = lib.mkOption { type = lib.types.str; };
      port = lib.mkOption { type = lib.types.port; default = 587; };
      tls = lib.mkOption { type = lib.types.bool; default = true; };
    };
  };

  ai = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable AI classification";
    };
    model = lib.mkOption {
      type = lib.types.str;
      default = "claude-sonnet-4-20250514";
      description = "Model name for OpenAI-compatible API";
    };
    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:18789";
    };
    temperature = lib.mkOption {
      type = lib.types.float;
      default = 0.3;
    };
    useDefaultTags = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use built-in 35-tag taxonomy";
    };
    labelPrefix = lib.mkOption {
      type = lib.types.str;
      default = "AI";
      description = "Prefix for AI-generated labels";
    };
  };

  sync = {
    maxMessagesPerSync = lib.mkOption {
      type = lib.types.int;
      default = 100;
    };
  };
};
```

## Requirements

### Requirement: Server/Client Role Support

PIM module SHALL support multi-host Tailnet deployments via role-based configuration.

#### Scenario: Server role (default)

- **Given**: User has `modules.pim = true`
- **And**: `pim.role = "server"` (default)
- **When**: NixOS configuration is evaluated
- **Then**: cairn-mail service is enabled
- **And**: AI module is required (assertion)
- **And**: Background sync is enabled
- **And**: SQLite database is local

#### Scenario: Client role (PWA only)

- **Given**: User has `modules.pim = true`
- **And**: `pim.role = "client"`
- **And**: `pim.pwa.tailnetDomain = "taile0fb4.ts.net"`
- **When**: NixOS configuration is evaluated
- **Then**: cairn-mail service is NOT installed
- **And**: AI module is NOT required
- **And**: PWA desktop entry points to `https://cairn-mail.${tailnetDomain}/`

> **Note**: Client assumes a server with Tailscale Services is running. Deploy server first.

### Requirement: AI Module Dependency (Server Role Only)

PIM server role MUST have the AI module enabled.

#### Scenario: Server role without AI

- **Given**: User has `modules.pim = true`
- **And**: `pim.role = "server"`
- **And**: User has `modules.ai = false`
- **When**: NixOS configuration is evaluated
- **Then**: An assertion error is raised
- **And**: Error message explains the dependency

#### Scenario: Client role without AI

- **Given**: User has `modules.pim = true`
- **And**: `pim.role = "client"`
- **And**: User has `modules.ai = false`
- **When**: NixOS configuration is evaluated
- **Then**: Configuration succeeds (no AI requirement for clients)

#### Scenario: Server role with AI (default)

- **Given**: User has `modules.pim = true`
- **And**: `pim.role = "server"`
- **And**: `modules.ai` defaults to `true`
- **When**: NixOS configuration is evaluated
- **Then**: Both modules are enabled successfully

### Requirement: AI-Powered Email Classification

cairn-mail SHALL provide local AI-powered email classification.

#### Scenario: New email arrives

- **Given**: User has cairn-mail configured with an AI backend
- **And**: AI classification is enabled (`ai.enable = true`)
- **When**: A new email is synced
- **Then**: The email is classified using the configured model
- **And**: Tags are applied with confidence scores
- **And**: Classification happens locally (no cloud API calls)

### Requirement: Declarative Account Configuration

Email accounts SHALL be configurable via Nix modules.

#### Scenario: Gmail account with OAuth

- **Given**: User configures `accounts.personal.provider = "gmail"`
- **And**: User provides `oauthTokenFile` path (agenix secret)
- **When**: System activates
- **Then**: Account is available in cairn-mail
- **And**: OAuth token is loaded securely from file

#### Scenario: IMAP account

- **Given**: User configures `accounts.work.provider = "imap"`
- **And**: User provides IMAP/SMTP settings and `passwordFile`
- **When**: System activates
- **Then**: Account is available in cairn-mail
- **And**: Password is loaded securely from file

### Requirement: Background Sync

cairn-mail SHALL provide automated background email synchronization.

#### Scenario: Periodic sync

- **Given**: `pim.sync.enable = true` (default)
- **And**: `pim.sync.frequency = "5m"`
- **When**: System is running
- **Then**: Emails sync every 5 minutes via systemd timer
- **And**: Pending operations (mark read, delete, etc.) are processed

### Requirement: Cross-Device Access

cairn-mail SHALL support secure cross-device access via Tailscale Services.

#### Scenario: Tailscale Services (server with authkey mode)

- **Given**: Server has `networking.tailscale.authMode = "authkey"`
- **And**: `pim.role = "server"`
- **And**: Device is connected to tailnet
- **When**: User accesses `https://cairn-mail.<tailnet>.ts.net`
- **Then**: User can access cairn-mail web UI securely
- **And**: Service is auto-registered via Tailscale Services

#### Scenario: Server-local access via loopback proxy

- **Given**: `pim.role = "server"`
- **And**: `loopbackProxy.enable = true` on the `cairn-mail` Tailscale service
- **When**: The server's browser navigates to `https://cairn-mail.<tailnet>.ts.net`
- **Then**: `/etc/hosts` resolves the FQDN to `127.0.0.1`
- **And**: nginx on `127.0.0.1:443` serves the request with a valid LE certificate
- **And**: nginx proxies the request to `http://127.0.0.1:<pim.port>/`
- **And**: The browser has a valid HTTPS secure context
- **And**: Web Push notifications (`PushManager.subscribe()`) succeed

### Requirement: Centralized PWA Registration

PIM module SHALL register its PWA via the `cairn.pwa.apps` option, delegating desktop entry generation to the desktop module.

#### Scenario: PWA Registration

- **Given**: `pim.pwa.enable = true`
- **When**: Configuration is evaluated
- **Then**: `cairn.pwa.apps.cairn-mail` is defined
- **And**: `url` is `https://cairn-mail.<tailnetDomain>/`
- **And**: `isolated` is `true` (uses dedicated profile)
- **And**: Browser selection is handled by `cairn.pwa.browser` (global setting)

### Requirement: Unified URL Strategy

PIM PWA SHALL use the same HTTPS URL for both server and client roles.

#### Scenario: Server URL Resolution

- **Given**: `pim.role = "server"`
- **And**: User launches PWA (`https://cairn-mail.<tailnet>/`)
- **When**: Request is made
- **Then**: `/etc/hosts` resolves domain to `127.0.0.1` (loopback proxy)
- **And**: Connection is secure (HTTPS)

#### Scenario: Client URL Resolution

- **Given**: `pim.role = "client"`
- **And**: User launches PWA
- **When**: Request is made
- **Then**: Tailscale DNS resolves domain to server VIP
- **And**: Connection is secure (HTTPS)


### Requirement: Tailscale Service Registration (Server)

PIM server role SHALL register an `cairn-mail` Tailscale service with loopback proxy enabled.

#### Scenario: Server role Tailscale service

- **Given**: `pim.role = "server"`
- **When**: NixOS configuration is evaluated
- **Then**: `networking.tailscale.services."cairn-mail"` is enabled
- **And**: `backend` is `http://127.0.0.1:${pim.port}`
- **And**: `loopbackProxy.enable` is `true`

## Constraints

- **AI Module Required (Server Only)**: PIM server role requires `modules.ai = true` (enforced via assertion)
- **Client Role Exempt**: PIM client role does NOT require AI module
- **AI Backend Required (Server Only)**: AI classification requires an OpenAI-compatible API endpoint
- **Tailscale Services**: Cross-device access uses Tailscale Services (`cairn-mail.<tailnet>.ts.net`)
- **Loopback Proxy (Server)**: Server role enables `loopbackProxy` for valid HTTPS secure context on localhost (enables Web Push API)
- **Server First**: Client role requires server with `authMode = "authkey"` to be deployed first
- **Secret Management**: Credentials MUST use file-based secrets (agenix, sops-nix)
- **No Hardcoded Accounts**: Account configuration is user-defined

## Troubleshooting

### OAuth Token Expired

**Symptom**: Gmail sync fails with authentication error

**Solution**:
```bash
cairn-mail auth gmail --account personal
# Follow OAuth flow in browser
```

### AI Classification Not Working

**Symptom**: Emails sync but have no AI tags

**Check**:
1. AI endpoint reachable: `curl -s http://localhost:18789/v1/models`
2. AI enabled: Check `programs.cairn-mail.ai.enable`
3. If using local inference: `systemctl status llama-server`

### Sync Service Not Running

**Symptom**: Emails not updating automatically

**Check**:
```bash
systemctl --user status cairn-mail-sync.timer
journalctl --user -u cairn-mail-sync
```

### PWA Not Appearing

**Symptom**: Desktop entry not showing in app launcher

**Check**:
1. `pim.pwa.enable = true` in config
2. `pim.pwa.tailnetDomain` is set
3. Run `update-desktop-database` or logout/login

## References

- **Port Allocations**: See `openspec/specs/networking/ports.md` for cairn port registry
  - Local port: 8080 (default)
  - Tailscale Services: `cairn-mail.<tailnet>.ts.net` (port 443)
- **AI Module**: See `openspec/specs/ai/spec.md` for local inference configuration
- **Loopback Proxy**: See `openspec/specs/networking/spec.md` for the generic loopback proxy mechanism
- **Upstream**: [cairn-mail repository](https://github.com/kcalvelli/cairn-mail)
