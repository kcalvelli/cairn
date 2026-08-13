{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.services.ai;
  isServer = cfg.local.role == "server";
  isClient = cfg.local.role == "client";
  tsCfg = config.networking.tailscale;
  useServices = tsCfg.authMode == "authkey";

  # GPU type detection (follows graphics module pattern)
  gpuType = config.cairn.hardware.gpuType or null;
  isAmdGpu = gpuType == "amd";
  isNvidiaGpu = gpuType == "nvidia";

  # llama.cpp package: ROCm for AMD, standard (CUDA) for Nvidia
  llamaPkg = if isAmdGpu then pkgs.llama-cpp-rocm else pkgs.llama-cpp;

  # Build llama-server command-line arguments from options
  serverArgs = [
    "--model"
    (toString cfg.local.model)
    "--ctx-size"
    (toString cfg.local.contextSize)
    "--port"
    (toString cfg.local.port)
    "--host"
    "0.0.0.0"
    "--n-gpu-layers"
    (toString cfg.local.gpuLayers)
  ]
  ++ cfg.local.extraArgs;
in
{
  options = {
    services.ai = {
      enable = lib.mkEnableOption "AI tools and services (claude-code, antigravity, codex)";

      mcp = {
        enable = lib.mkEnableOption "Model Context Protocol (MCP) server integration" // {
          default = true;
        };

        gatewayUrl = lib.mkOption {
          type = lib.types.str;
          default = "";
          defaultText = lib.literalExpression ''
            if services.ai.local.role == "client"
            then "https://cairn-mcp-gateway.''${services.ai.local.tailnetDomain}"
            else "http://127.0.0.1:''${toString services.mcp-gateway.port}"
          '';
          description = ''
            Base URL of the cairn MCP gateway used by AI tools (claude-code,
            codex, etc.) and exported to the user environment as
            MCP_GATEWAY_URL. Consumers that need the MCP-over-HTTP transport
            endpoint append "/mcp" to this base URL.

            Default is computed from services.ai.local.role:
              - "server": local gateway at http://127.0.0.1:<gatewayPort>
              - "client": Tailscale Service at
                          https://cairn-mcp-gateway.<tailnetDomain>

            Override only if you have a non-standard gateway deployment.
          '';
        };
      };

      # Per-tool enablement (all default to true for backward compatibility)
      claude = {
        enable = lib.mkEnableOption "Claude Code";
      };

      gemini = {
        enable = lib.mkEnableOption "Antigravity CLI (successor to the retired Gemini CLI)";
      };

      workflow = {
        enable = lib.mkEnableOption "spec-driven development workflow tools (openspec, spec-kit)";
      };

      openai = {
        enable = lib.mkEnableOption "OpenAI Codex CLI";

        codexAcp = {
          enable = lib.mkEnableOption "Codex ACP companion";
        };
      };

      xai = {
        enable = lib.mkEnableOption "Grok CLI (xAI)";
      };

      # Unified system prompt
      systemPrompt = {
        enable = lib.mkEnableOption "unified system prompt for AI agents" // {
          default = true;
        };

        extraInstructions = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Additional custom instructions appended to the Cairn system prompt.
            These are added under the "Custom User Instructions" section.

            Example:
              services.ai.systemPrompt.extraInstructions = '''
                ## Project Standards
                - Use Rust for performance-critical code
                - Include integration tests
                - Follow conventional commits
              ''';
          '';
          example = ''
            ## My Coding Rules
            - Prefer functional patterns
            - Always add comprehensive error handling
          '';
        };
      };

      local = {
        enable = lib.mkEnableOption "local LLM inference stack (llama.cpp, OpenCode)";

        role = lib.mkOption {
          type = lib.types.enum [
            "server"
            "client"
          ];
          default = "server";
          description = ''
            Local LLM deployment role:
            - "server": Run llama-server locally with GPU acceleration
                        Auto-registers as cairn-llama.<tailnet>.ts.net via Tailscale Services
            - "client": Use remote llama-server via Tailscale Services (no local GPU required)
          '';
        };

        # Client role options
        tailnetDomain = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "taile0fb4.ts.net";
          description = "Tailscale tailnet domain";
        };

        model = lib.mkOption {
          type = lib.types.path;
          description = ''
            Absolute path to a GGUF model file.
            Download models with: nix run .#download-llama-models
          '';
          example = "/var/lib/llama-models/mistral-7b-instruct-v0.3.Q4_K_M.gguf";
        };

        contextSize = lib.mkOption {
          type = lib.types.int;
          default = 32768;
          description = "Context window size in tokens.";
        };

        port = lib.mkOption {
          type = lib.types.port;
          default = 11434;
          description = "Port for llama-server to listen on.";
        };

        gpuLayers = lib.mkOption {
          type = lib.types.int;
          default = -1;
          description = ''
            Number of layers to offload to GPU. -1 offloads all layers.
            Set to 0 to run on CPU only.
          '';
        };

        extraArgs = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional command-line arguments passed to llama-server.";
          example = [
            "--flash-attn"
            "--threads"
            "8"
          ];
        };

        cli = lib.mkEnableOption "OpenCode agentic CLI" // {
          default = true;
        };
      };
    };
  };

  config = lib.mkMerge [
    # Assertions for role and configuration validation
    {
      assertions = [
        # Client role requires tailnetDomain for Tailscale Services DNS
        {
          assertion = !(cfg.enable && cfg.local.enable && isClient) || cfg.local.tailnetDomain != null;
          message = ''
            services.ai.local.role = "client" requires tailnetDomain to be set.

            Example:
              services.ai.local.tailnetDomain = "taile0fb4.ts.net";
          '';
        }
        # Server role requires authkey mode for Tailscale Services
        {
          assertion = !(cfg.enable && cfg.local.enable && isServer) || useServices;
          message = ''
            services.ai.local.role = "server" requires networking.tailscale.authMode = "authkey".

            Server role uses Tailscale Services for HTTPS, which requires tag-based identity.
            Set up an auth key in the Tailscale admin console with appropriate tags.
          '';
        }
      ];
    }

    # MCP gateway URL — computed default, overridable.
    # Server hosts hit the local gateway over loopback; client hosts hit
    # the cairn-mcp-gateway Tailscale Service. Both consumers (the
    # MCP_GATEWAY_URL session var below and the home-manager mcp_servers.json
    # generator) read this single value.
    (lib.mkIf (cfg.enable && cfg.mcp.enable) {
      services.ai.mcp.gatewayUrl = lib.mkDefault (
        if cfg.local.enable && isClient then
          "https://cairn-mcp-gateway.${cfg.local.tailnetDomain}"
        else
          "http://127.0.0.1:${toString (config.services.mcp-gateway.port or 8085)}"
      );
    })

    # Base AI configuration (always enabled when services.ai.enable = true)
    (lib.mkIf cfg.enable {
      # Add users to systemd-journal group using userGroups
      # This avoids infinite recursion by not modifying users.users directly
      users.groups.systemd-journal = {
        members = lib.attrNames (
          lib.filterAttrs (_name: user: user.isNormalUser or false) config.users.users
        );
      };

      # AI tools and packages
      environment.systemPackages =
        with pkgs;
        [
          # Core AI tools (always installed when services.ai.enable = true)
          whisper-cpp # Speech-to-text
        ]
        # Claude Code (conditional on services.ai.claude.enable)
        ++ lib.optionals cfg.claude.enable [
          claude-code # Anthropic - MCP support, deep integration
          claude-desktop # Anthropic's official native Linux build (cairn-packaged)
          claude-code-router # Claude Code request router
          claude-monitor # Real-time Claude Code usage monitoring
          # VSCode extension compatibility: claude-code symlink
          (writeShellScriptBin "claude-code" ''
            exec ${claude-code}/bin/claude "$@"
          '')
        ]
        # Antigravity CLI (conditional on services.ai.gemini.enable)
        # Google retired gemini-cli and replaced it with Antigravity CLI.
        ++ lib.optionals cfg.gemini.enable [
          inputs.antigravity-nix.packages.x86_64-linux.default
        ]
        # OpenAI Codex (conditional on services.ai.openai.enable)
        ++ lib.optionals cfg.openai.enable [
          codex
        ]
        ++ lib.optionals (cfg.openai.enable && cfg.openai.codexAcp.enable) [
          codex-acp
        ]
        # Grok CLI (conditional on services.ai.xai.enable)
        ++ lib.optionals cfg.xai.enable [
          grok-cli # xAI - grok / agent, beta channel, cairn-packaged
        ]
        # Workflow tools (conditional on services.ai.workflow.enable)
        ++ lib.optionals cfg.workflow.enable [
          spec-kit # Spec-driven development framework
          openspec # OpenSpec CLI tool for SDD workflow
        ];
    })

    # Claude Desktop is Electron; its bundled chrome-sandbox can't be setuid
    # from the nix store, so give it NixOS's setuid sandbox helper and keep the
    # renderer sandbox ON. The package wrapper points CHROME_DEVEL_SANDBOX at
    # /run/wrappers/bin/__chromium-suid-sandbox, which this provides.
    (lib.mkIf (cfg.enable && cfg.claude.enable) {
      security.chromiumSuidSandbox.enable = lib.mkDefault true;
    })

    # Shared local LLM packages (both server and client roles)
    (lib.mkIf (cfg.enable && cfg.local.enable) {
      environment.systemPackages = with pkgs; [
        python3
        uv # Python package manager for uvx
      ];
    })

    # Server role: Local llama-server with GPU acceleration
    (lib.mkIf (cfg.enable && cfg.local.enable && isServer) {
      # llama-server systemd service
      systemd.services.llama-server = {
        description = "llama.cpp inference server";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];

        environment = lib.optionalAttrs isAmdGpu {
          HSA_OVERRIDE_GFX_VERSION = "10.3.0";
        };

        serviceConfig = {
          ExecStart = "${llamaPkg}/bin/llama-server ${lib.escapeShellArgs serverArgs}";
          Restart = "on-failure";
          RestartSec = 5;
          DynamicUser = true;
          StateDirectory = "llama-server";
        };
      };

      # Kernel modules (AMD-specific)
      boot.kernelModules = lib.optionals isAmdGpu [ "amdgpu" ];

      # Server role packages (GPU stack + LLM tools)
      environment.systemPackages =
        with pkgs;
        # AMD-specific: ROCm debugging tools
        lib.optionals isAmdGpu [ rocmPackages.rocminfo ] ++ lib.optional cfg.local.cli pkgs.opencode;

      # Tailscale Services registration
      networking.tailscale.services."cairn-llama" = {
        enable = true;
        backend = "http://127.0.0.1:${toString cfg.local.port}";
      };

      # Local hostname for server access (hairpinning workaround)
      networking.hosts = {
        "127.0.0.1" = [ "cairn-llama.local" ];
      };
    })

    # Client role: Remote llama-server via Tailscale Services
    (lib.mkIf (cfg.enable && cfg.local.enable && isClient) {
      environment.sessionVariables = {
        LLAMA_API_URL = "https://cairn-llama.${cfg.local.tailnetDomain}";
        MCP_GATEWAY_URL = cfg.mcp.gatewayUrl;
      };

      # Client role packages (lighter footprint, no GPU stack)
      environment.systemPackages = lib.optional cfg.local.cli pkgs.opencode;
    })
  ];
}
