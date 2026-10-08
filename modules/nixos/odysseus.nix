# Odysseus - self-hosted AI workspace.
# https://github.com/odysseus-dev/odysseus
#
# Runs the official container image under podman (via
# virtualisation.oci-containers), next to the same helper services that
# upstream's docker-compose.yml bundles: ChromaDB (vector memory) and
# SearXNG (web search). All three share a private podman network, so the
# only thing published on the host is the Odysseus web UI.
#
# Minimal use:
#
#   services.odysseus.enable = true;
#
# The first admin password is printed once on first boot:
#
#   journalctl -u podman-odysseus | grep -i password
#
# Secrets (API keys, a pre-seeded admin password, ...) go in a file that is
# NOT in the nix store and is passed with `environmentFiles`:
#
#   # /var/lib/odysseus-secrets.env   (chmod 600, owned by root)
#   ODYSSEUS_ADMIN_PASSWORD=...
#   OPENAI_API_KEY=...
#
# Note on exposure: podman publishes ports with its own NAT rules, which
# bypass the NixOS firewall's INPUT chain. `bindAddress` is the real
# access control here, not `networking.firewall`.
{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatStringsSep
    genAttrs
    mkDefault
    mkEnableOption
    mkIf
    mkOption
    optional
    optionalAttrs
    types
    ;

  cfg = config.services.odysseus;

  network = "odysseus";

  # Container names. oci-containers turns each into a podman-<name>.service.
  containerNames =
    ["odysseus" "odysseus-chromadb"]
    ++ optional cfg.searxng.enable "odysseus-searxng";

  # Odysseus needs SearXNG's JSON output format switched on, which the stock
  # settings don't do. Everything else stays at SearXNG's defaults.
  searxngSettings = (pkgs.formats.yaml {}).generate "searxng-settings.yml" {
    use_default_settings = true;
    general.instance_name = "Odysseus search";
    search.formats = ["html" "json"];
    server = {
      limiter = false;
      public_instance = false;
      image_proxy = false;
    };
  };

  secretFile = "${cfg.dataDir}/searxng-secret.env";

  # Numeric so it also works when createUser is off and uid/gid belong to an
  # account defined elsewhere.
  owner = "${toString cfg.uid} ${toString cfg.gid}";
in {
  options.services.odysseus = {
    enable = mkEnableOption "Odysseus, a self-hosted AI workspace";

    image = mkOption {
      type = types.str;
      default = "ghcr.io/odysseus-dev/odysseus:latest";
      example = "ghcr.io/odysseus-dev/odysseus:1.0.2-7c8070f";
      description = ''
        Container image. `:latest` moves on every push to upstream's main
        branch, so for anything you care about, pin the immutable
        `X.Y.Z-<sha>` tag instead.
      '';
    };

    port = mkOption {
      type = types.port;
      default = 7000;
      description = "Host port the web UI is published on.";
    };

    bindAddress = mkOption {
      type = types.str;
      default = "127.0.0.1";
      example = "0.0.0.0";
      description = ''
        Host address the web UI is published on. Keep it on loopback and put
        a reverse proxy / VPN in front, or set it to a LAN / Tailscale
        address (or "0.0.0.0") if you want to reach it directly. Odysseus is
        effectively an admin console (shell access, file uploads, API
        tokens), so keep authentication on and don't expose it to the
        internet.
      '';
    };

    dataDir = mkOption {
      type = types.path;
      default = "/var/lib/odysseus";
      description = ''
        Where everything persistent lives: the app's data/ and logs/, the
        Cookbook SSH key, model cache and installed serve engines, plus
        ChromaDB's and SearXNG's state.
      '';
    };

    uid = mkOption {
      type = types.int;
      default = 3500;
      description = "UID of the `odysseus` user the app drops to inside the container.";
    };

    gid = mkOption {
      type = types.int;
      default = 3500;
      description = "GID of the `odysseus` group the app drops to inside the container.";
    };

    createUser = mkOption {
      type = types.bool;
      default = true;
      description = ''
        Create a dedicated `odysseus` user/group with the uid/gid above. Turn
        this off if you set uid/gid to an existing account instead, e.g. your
        own, so files in `workspaceDir` are owned by you.
      '';
    };

    workspaceDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/home/alice/Odysseus";
      description = ''
        Host folder mounted into the container at /workspace, for the agent
        and file tools to read and write. Without this, the container only
        sees its own filesystem, never your files. The folder is created if
        missing and owned by `uid`/`gid`.
      '';
    };

    allowedOrigins = mkOption {
      type = types.listOf types.str;
      default = ["http://localhost" "http://127.0.0.1"];
      description = ''
        Exact origins allowed for cross-origin browser/API clients
        (ALLOWED_ORIGINS). Ordinary same-origin access, including through a
        reverse proxy, doesn't need an entry here.
      '';
    };

    environment = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        OLLAMA_BASE_URL = "http://host.docker.internal:11434/v1";
        OAUTH_REDIRECT_BASE_URL = "https://odysseus.example.com";
      };
      description = ''
        Extra, non-secret environment variables for the app (see upstream's
        .env.example). These win over the ones this module sets. The host
        is reachable from inside the container as `host.docker.internal`.
      '';
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [];
      example = ["/var/lib/odysseus-secrets.env"];
      description = ''
        Files of KEY=value lines passed to the app container. Use these for
        anything secret so it stays out of the world-readable nix store.
        Give them as strings, not as nix path literals.
      '';
    };

    chromadb.image = mkOption {
      type = types.str;
      default = "docker.io/chromadb/chroma:latest";
      description = "ChromaDB image, used for Odysseus' vector memory.";
    };

    searxng = {
      enable =
        mkEnableOption "the bundled SearXNG instance used for web search"
        // {default = true;};

      image = mkOption {
        type = types.str;
        # Upstream pins this on purpose: odysseus waits on searxng, and a
        # newer tag (2026.6.2) crashed on boot. Bump it deliberately.
        default = "docker.io/searxng/searxng:2026.5.31-7159b8aed";
        description = "SearXNG image. Pinned like upstream's compose file; bump deliberately.";
      };
    };
  };

  config = mkIf cfg.enable {
    # This module only knows how to talk to podman.
    virtualisation.oci-containers.backend = mkDefault "podman";

    users.groups = mkIf cfg.createUser {
      odysseus.gid = cfg.gid;
    };
    users.users = mkIf cfg.createUser {
      odysseus = {
        isSystemUser = true;
        uid = cfg.uid;
        group = "odysseus";
        description = "Odysseus AI workspace";
      };
    };

    systemd.tmpfiles.rules =
      [
        "d ${cfg.dataDir} 0755 root root -"
        "d ${cfg.dataDir}/data 0750 ${owner} -"
        "d ${cfg.dataDir}/logs 0750 ${owner} -"
        "d ${cfg.dataDir}/data/ssh 0700 ${owner} -"
        "d ${cfg.dataDir}/data/huggingface 0750 ${owner} -"
        "d ${cfg.dataDir}/data/local 0750 ${owner} -"
        "d ${cfg.dataDir}/chromadb 0755 root root -"
      ]
      ++ optional cfg.searxng.enable "d ${cfg.dataDir}/searxng 0755 root root -"
      ++ optional (cfg.workspaceDir != null) "d ${cfg.workspaceDir} 0755 ${owner} -";

    virtualisation.oci-containers.containers =
      {
        odysseus = {
          image = cfg.image;
          ports = ["${cfg.bindAddress}:${toString cfg.port}:7000"];
          volumes = [
            "${cfg.dataDir}/data:/app/data"
            "${cfg.dataDir}/logs:/app/logs"
            # Cookbook's remote-server SSH identity.
            "${cfg.dataDir}/data/ssh:/app/.ssh"
            # Cookbook's local model cache.
            "${cfg.dataDir}/data/huggingface:/app/.cache/huggingface"
            # Cookbook-installed serve engines (vLLM, llama-cpp-python, ...),
            # persisted so recreating the container doesn't wipe them.
            "${cfg.dataDir}/data/local:/app/.local"
          ]
          ++ optional (cfg.workspaceDir != null) "${cfg.workspaceDir}:/workspace";
          environment =
            {
              PUID = toString cfg.uid;
              PGID = toString cfg.gid;
              AUTH_ENABLED = "true";
              LOCALHOST_BYPASS = "false";
              ALLOWED_ORIGINS = concatStringsSep "," cfg.allowedOrigins;
              CHROMADB_HOST = "chromadb";
              CHROMADB_PORT = "8000";
            }
            // optionalAttrs cfg.searxng.enable {
              SEARXNG_INSTANCE = "http://searxng:8080";
            }
            // cfg.environment;
          environmentFiles = cfg.environmentFiles;
          dependsOn =
            ["odysseus-chromadb"]
            ++ optional cfg.searxng.enable "odysseus-searxng";
          extraOptions = [
            "--network=${network}"
            # Lets the container reach services on the host, e.g. Ollama at
            # http://host.docker.internal:11434 (Ollama must listen on
            # something other than its own loopback for this to work).
            "--add-host=host.docker.internal:host-gateway"
          ];
        };

        odysseus-chromadb = {
          image = cfg.chromadb.image;
          volumes = ["${cfg.dataDir}/chromadb:/chroma/chroma"];
          environment.ANONYMIZED_TELEMETRY = "FALSE";
          # No published port: only the app talks to it, over the network.
          extraOptions = [
            "--network=${network}"
            "--network-alias=chromadb"
          ];
        };
      }
      // optionalAttrs cfg.searxng.enable {
        odysseus-searxng = {
          image = cfg.searxng.image;
          volumes = ["${cfg.dataDir}/searxng:/etc/searxng"];
          environmentFiles = [secretFile];
          extraOptions = [
            "--network=${network}"
            "--network-alias=searxng"
            # Same capability set upstream's compose file uses: the image's
            # entrypoint chowns /etc/searxng and drops privileges on boot.
            "--cap-drop=ALL"
            "--cap-add=CHOWN"
            "--cap-add=SETGID"
            "--cap-add=SETUID"
            "--cap-add=DAC_OVERRIDE"
          ];
        };
      };

    systemd.services =
      {
        # One-shot prep that has to happen before any of the containers:
        # the private network, SearXNG's settings, and its secret key.
        odysseus-init = {
          description = "Prepare podman network and config for Odysseus";
          path = [config.virtualisation.podman.package pkgs.coreutils pkgs.openssl];
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
          };
          script =
            ''
              podman network exists ${network} || podman network create ${network}
            ''
            + lib.optionalString cfg.searxng.enable ''
              install -d -m 0755 ${cfg.dataDir}/searxng
              install -m 0644 ${searxngSettings} ${cfg.dataDir}/searxng/settings.yml

              # Generated once and then kept, so SearXNG's secret key is
              # stable across restarts without ever entering the nix store.
              if [ ! -s ${secretFile} ]; then
                (umask 077; echo "SEARXNG_SECRET=$(openssl rand -hex 32)" > ${secretFile})
              fi
            '';
        };
      }
      // genAttrs (map (name: "podman-${name}") containerNames) (_: {
        requires = ["odysseus-init.service"];
        after = ["odysseus-init.service"];
      });
  };
}
