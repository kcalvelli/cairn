# AI & Development Assistance

## Purpose
Integrates advanced AI agents and local inference capabilities into the developer workflow, prioritizing efficiency and context-awareness.

## Components

### CLI Coding Agents
- **Claude Ecosystem**:
    - `claude-code`: Primary CLI agent with deep MCP integration.
    - `claude-code-acp`: Agent Communication Protocol support.
    - `claude-code-router`: Request routing for Claude services.
    - `claude-desktop`: Desktop integration layer.
- **Gemini Ecosystem**:
    - `gemini-cli-bin`: Multimodal CLI agent.
    - **Authentication**: Uses an OAuth flow for Pro accounts (`gemini auth login`). API keys are not recommended for Pro users as they bypass the subscription.
    - **Configuration**: System prompt is managed via the `GEMINI_SYSTEM_MD` environment variable, set declaratively in `home/ai/mcp.nix`.
    - `antigravity`: Advanced agentic assistant for Cairn development.
- **OpenAI Ecosystem**:
    - `codex`: Terminal coding agent.
    - `codex-acp`: Optional ACP-compatible companion for tool integrations that speak Agent Communication Protocol.
    - **Authentication**: Uses the upstream interactive login flow (`codex login`).
    - **Configuration**: MCP access is managed declaratively via `~/.codex/config.toml`, generated from `home/ai/mcp.nix` when OpenAI tooling and MCP are enabled.
    - `chatgpt` PWA: Standalone user-facing ChatGPT app available through the desktop/PWA workflow, outside the AI power-user stack.
- **xAI Ecosystem**:
    - `grok-cli`: Grok coding agent, exposing both the `grok` and `agent` entrypoints. Beta (alpha-channel) build, vendored as a pinned closed-source prebuilt binary in `pkgs/grok-cli` rather than via the upstream `curl | bash` installer.
    - **Packaging**: A static-pie binary fetched from the `grok-build-public-artifacts` GCS bucket; no `autoPatchelfHook` required. Version + sha256 are pinned manually (no auto-update), and shell completions (bash/zsh/fish) are generated at build time.
    - **Enablement**: Gated behind `services.ai.xai.enable` (off by default), alongside the `claude`/`gemini`/`openai` per-tool toggles.
- **Workflow Tools**:
    - `openspec`: OpenSpec SDD workflow CLI for spec-driven development.
    - `whisper-cpp`: Speech-to-text.
    - `claude-monitor`: Resource monitoring for AI sessions.
- **Implementation**: `modules/ai/default.nix`, `home/ai/`, `pkgs/pwa-apps/pwa-defs.nix`, `home/resources/pwa-icons/chatgpt.png`

### System Prompt Management
- **Unified Prompt**: Cairn provides a system prompt at `~/.config/ai/prompts/cairn.md` containing PIM domain hints and custom user instructions.
- **Auto-Injection**: Automatically injected into `~/.claude.json` during system activation.
- **Customization**: Users can append instructions via `services.ai.systemPrompt.extraInstructions`.

### Model Context Protocol (MCP)
- **Token Reduction Strategy**: Claude Code uses built-in tools only; MCP servers are accessed on-demand via mcp-gateway's `/mcp-cli` skill and REST API, reducing context window usage by up to 99%.
- **No Native MCP**: `~/.mcp.json` generation is disabled by default (`generateClaudeConfig = false`). Claude Code does not spawn MCP servers natively.
- **mcp-gw**: The `mcp-gw` CLI binary, `/mcp-cli` skill, and all related configuration are fully owned by the mcp-gateway module (not cairn). cairn does not package or patch any CLI tool for MCP discovery.
- **Servers**: Git, GitHub, Filesystem, Journal, Nix-devshell, etc.
- **Configuration**: Declarative via `services.mcp-gateway` (from external mcp-gateway repo).
- **Implementation**: Server definitions in `home/ai/mcp.nix`, module logic in `github.com/kcalvelli/mcp-gateway`

### Local Inference Stack (llama.cpp)

**Deployment Roles:**

The local LLM stack supports server/client architecture for distributed inference using `llama-server` from llama.cpp:

- **Server Role** (`role = "server"`, default):
  - Runs `llama-server` locally with GPU acceleration
  - Supports both AMD (`llama-cpp-rocm`) and Nvidia (`llama-cpp` with CUDA) GPUs
  - Auto-registers as `cairn-llama.<tailnet>.ts.net` via Tailscale Services
  - Loads a single GGUF model file directly (no model management layer)

- **Client Role** (`role = "client"`):
  - Connects to remote llama-server via Tailscale Services
  - No local GPU stack installed (lighter footprint)
  - Sets `LLAMA_API_URL` to `https://cairn-llama.<tailnet>.ts.net`
  - Only requires `tailnetDomain` configuration
  - Ideal for lightweight laptops using a desktop as inference server

> **Note**: Client role requires a server with `networking.tailscale.authMode = "authkey"` running on the tailnet. The server must be deployed first to register the Tailscale Services.

**Model Management**: Users download GGUF models via `nix run .#download-llama-models` and configure the path:
```nix
services.ai.local.model = "/var/lib/llama-models/mistral-7b-instruct-v0.3.Q4_K_M.gguf";
```

**Multi-Vendor GPU Support:**

The server role automatically detects GPU vendor from the host's `hardware.gpu` configuration:

| Aspect | AMD | Nvidia |
|--------|-----|--------|
| Package | `llama-cpp-rocm` | `llama-cpp` (CUDA) |
| Flash Attention | Off by default (opt-in via `--flash-attn`) | Off by default |
| Architecture Override | `HSA_OVERRIDE_GFX_VERSION` env var | N/A |
| Kernel Modules | `amdgpu` | (via nixos-hardware) |
| Debug Tools | `rocmPackages.rocminfo` | N/A |

```nix
# Host config determines GPU vendor (no additional AI module config needed)
{ hardware.gpu = "amd"; }   # Uses llama-cpp-rocm
{ hardware.gpu = "nvidia"; } # Uses llama-cpp with CUDA
```

**API**: OpenAI-compatible `/v1/chat/completions` endpoint, served by `llama-server`.

**Context Window**: Configurable via `services.ai.local.contextSize` (default: 32768 tokens).

**GPU Offload**: Configurable via `services.ai.local.gpuLayers` (default: -1, all layers).

**Network Access**:
- **Tailscale Services**: Auto-registers as `cairn-llama.<tailnet>.ts.net` on port 443.

**Implementation**: `modules/ai/default.nix` (custom `systemd.services.llama-server` unit)

### MCP Gateway (External Repository)

REST API gateway that exposes cairn MCP servers via OpenAPI endpoints and MCP HTTP transport.

**Repository**: `github.com/kcalvelli/mcp-gateway`

**Purpose**:
- Bridge between cairn MCP ecosystem and tools that don't natively support MCP
- Provide MCP HTTP transport for Claude.ai Integrations and Claude Desktop
- Own the declarative MCP configuration module (single source of truth)

**Architecture:**

mcp-gateway is a standalone repository that provides:
- **Package**: `mcp-gateway` Python FastAPI application
- **Home-Manager Module**: Declarative MCP server configuration

cairn imports mcp-gateway's module and layers on cairn-specific features:
- **System Prompts**: `cairn.md` (in `home/ai/prompts/`) — PIM domain hints and custom user instructions
- **OpenSpec Commands**: `/proposal`, `/apply`, `/archive` (in `home/ai/commands/`)
- **Global CLAUDE.md**: `~/.claude/CLAUDE.md` with `@import` of cairn prompt

```
┌─────────────────────────────────────────────────────────────────┐
│                   cairn (home/ai/mcp.nix)                       │
│  - Imports mcp-gateway's home-manager module                    │
│  - Provides server definitions with resolved nix store paths    │
│  - Adds system prompts (PIM hints), commands, ~/.claude/CLAUDE.md│
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    mcp-gateway module                           │
│  - Evaluates server declarations                                │
│  - Generates ~/.config/mcp/mcp_servers.json                     │
│  - Installs mcp-gw binary + /mcp-cli skill for Claude Code     │
│  - Configures systemd service                                   │
└─────────────────────────────────────────────────────────────────┘
```

**API Endpoints:**
- `GET /api/servers` - List all configured MCP servers
- `PATCH /api/servers/{id}` - Enable/disable a server
- `GET /api/tools` - List all available tools
- `POST /api/tools/{server}/{tool}` - Execute a tool
- `GET /health` - Health check
- `GET /mcp` - MCP HTTP transport endpoint (SSE)
- `POST /mcp/message` - MCP message endpoint

**Configuration** (via mcp-gateway home-manager module):
```nix
services.mcp-gateway = {
  enable = true;
  port = 8085;
  autoEnable = [ "git" "github" "filesystem" "context7" ];

  servers = {
    git = {
      enable = true;
      command = "${pkgs.mcp-server-git}/bin/mcp-server-git";
    };
    github = {
      enable = true;
      command = "${pkgs.github-mcp-server}/bin/github-mcp-server";
      args = [ "stdio" ];
      passwordCommand.GITHUB_PERSONAL_ACCESS_TOKEN = [ "gh" "auth" "token" ];
    };
    # ... more servers
  };
};
```

**Port Allocations:**
| Service | Local Port | Tailscale Services |
|---------|------------|-------------------|
| MCP Gateway | 8085 | cairn-mcp-gateway (443) |

**Implementation**:
- Repository: `github.com/kcalvelli/mcp-gateway`
- cairn integration: `home/ai/mcp.nix`

**SDK Architecture:**
The MCP Gateway uses official MCP SDK libraries for protocol compliance:
- **Client**: Uses `mcp` package (`mcp.client.stdio`, `ClientSession`) for connecting to MCP servers
- **Servers**: cairn MCP servers use `fastmcp` or `mcp.server.fastmcp` for the server side

| Component | SDK | Package |
|-----------|-----|---------|
| mcp-gateway (client) | `mcp` | `python3Packages.mcp` |
| mcp-dav (server) | `fastmcp` | `python3Packages.fastmcp` |
| cairn-mail (server) | `mcp.server.fastmcp` | `python3Packages.mcp` |

**Features:**
- `passwordCommand` support for secure secret retrieval (e.g., `gh auth token`)
- MCP HTTP transport for Claude.ai Integrations
- Automatic npx server support (bash, nodejs in service PATH)
- Non-blocking auto-enable on startup
- Generates configs for Gemini CLI and mcp-gw (`~/.config/mcp/mcp_servers.json`)
- `generateClaudeConfig` (default: `false`) — controls `~/.mcp.json` generation
- `generateClaudeSkill` (default: `true`) — installs `/mcp-cli` skill to `~/.claude/commands/mcp-cli.md`
- Provides `mcp-gw` binary via `home.packages`
- OpenAI Codex is exposed declaratively via `services.ai.openai`, while ChatGPT is shipped as a default PWA and does not depend on `services.ai.openai.enable`

## Requirements

### Requirement: OpenAI ecosystem tooling parity

The AI module SHALL expose OpenAI ecosystem tooling at the same vendor-selection layer as Claude and Gemini. It SHALL provide a `services.ai.openai.enable` option and SHALL install a baseline OpenAI terminal agent from `nixpkgs` when that option is enabled. This addition SHALL preserve the existing Claude and Gemini paths.

#### Scenario: OpenAI vendor tooling is enabled

- **WHEN** a user sets `services.ai.enable = true` and `services.ai.openai.enable = true`
- **THEN** the evaluated system configuration includes the baseline OpenAI terminal agent package from `nixpkgs`
- **AND** the OpenAI tooling is selected through a dedicated `services.ai.openai` namespace rather than an ad hoc package list

#### Scenario: OpenAI vendor tooling is disabled

- **WHEN** a user leaves `services.ai.openai.enable = false`
- **THEN** the evaluated system configuration does not add the primary OpenAI terminal agent package
- **AND** existing Claude and Gemini behavior remains unchanged

### Requirement: OpenAI companion tools remain explicit choices

The AI module SHALL expose additional OpenAI ecosystem tools from `nixpkgs` as explicit companion choices under `services.ai.openai`, rather than installing every available OpenAI-related package by default. User-facing desktop applications that are intentionally provided outside the AI workflow are not required to hang off this namespace.

#### Scenario: Companion tools are not installed implicitly

- **WHEN** a user enables `services.ai.openai.enable = true` without enabling any companion suboptions
- **THEN** only the baseline OpenAI tooling defined by the module is installed
- **AND** optional companion tools remain absent from the evaluated package set

#### Scenario: Companion tools can be enabled declaratively

- **WHEN** a user enables an OpenAI companion suboption exposed by the module
- **THEN** the corresponding `nixpkgs` package is added to the evaluated configuration
- **AND** the package is selected without requiring an additional flake input

#### Scenario: ChatGPT PWA can exist outside the AI module

- **WHEN** cairn provides ChatGPT through a non-AI user workflow such as the normie profile
- **THEN** that application is not required to depend on `services.ai.openai.enable`
- **AND** the broader AI CLI and MCP tooling remain separately scoped

### Requirement: OpenAI tooling guidance is documented

cairn SHALL document the supported OpenAI tools, their authentication expectations, and any prompt/configuration integration limitations alongside the existing AI tooling guidance.

#### Scenario: Authentication requirements are discoverable

- **WHEN** a user reads the AI module documentation or spec-backed guidance for OpenAI tooling
- **THEN** the documentation explains how the selected OpenAI tools authenticate
- **AND** any recommended secret handling follows existing cairn guidance rather than introducing a separate credential system

#### Scenario: Unsupported declarative hooks are called out

- **WHEN** an OpenAI tool does not support stable declarative prompt or config injection
- **THEN** cairn documents that limitation explicitly
- **AND** the implementation does not rely on undocumented or brittle wrapper behavior

## Constraints
- **Secrets**: API keys (e.g., `BRAVE_API_KEY`) SHOULD be set via `agenix` for security. Fallback to environment variables is provided. `gemini` Pro accounts should use OAuth (`gemini auth login`) instead of API keys.
- **GPU Recovery**: AMD GPU hang recovery enabled by default via graphics module; prevents hard freezes from GPU hangs.
- **Model Size**: Models larger than available VRAM trigger CPU offload, causing ROCm queue evictions and degraded performance. Control offload with `services.ai.local.gpuLayers`.

## Model Size Guidance

| VRAM | Recommended Max Model | Examples |
|------|----------------------|----------|
| 8 GB | 7B-8B parameters | Mistral 7B, Phi-3 |
| 12 GB | 14B parameters | Qwen 2.5 14B, DeepSeek Coder 16B |
| 16 GB | 22B-30B parameters | Qwen 2.5 32B |
| 24 GB | 70B parameters | Large coding models |

Download models with `nix run .#download-llama-models` and configure:
```nix
services.ai.local.model = "/var/lib/llama-models/mistral-7b-instruct-v0.2.Q4_K_M.gguf";
```

**Warning**: Running models larger than VRAM causes partial CPU offload, which creates excessive ROCm compute queues and triggers "queue evicted" kernel warnings. This can lead to system instability.

## GPU Troubleshooting

### Symptoms: "queue evicted" kernel warnings

**Cause**: ROCm compute queue oversubscription from multiple GPU processes or oversized models.

**Mitigations**:
1. Reduce `gpuLayers` to offload fewer layers to GPU
2. Avoid models that require CPU offload
3. Check `amd_smi` or `rocm-smi` for VRAM usage before loading large models

## References

- **Port Allocations**: See `openspec/specs/networking/ports.md` for cairn port registry
  - llama-server API: Local 11434, Tailscale via `cairn-llama`
- **PIM Module**: See `openspec/specs/pim/spec.md` for cairn-mail (uses OpenAI-compatible API)
- **Crash Diagnostics**: See `openspec/specs/hardware/crash-diagnostics.md` for GPU hang recovery
