{pkgs, ...}: {
  services.ollama = {
    enable = true;
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "49152";
      OLLAMA_KEEP_ALIVE = "24h";
    };
    package = pkgs.ollama-rocm; # AMD GPU build
    # Must listen beyond loopback, or the Odysseus container can't reach it.
    host = "0.0.0.0";

    # The RX 6700 XT (gfx1031) isn't officially supported by ROCm; this makes
    # it use the gfx1030 kernels, which work on it.
    rocmOverrideGfx = "10.3.0";

    # Models live on the SSD (via the bind mount below).
    models = "/var/lib/ollama-models";
    # Fixed user instead of a dynamic one, so the folder can be owned by it.
    user = "ollama";
    group = "ollama";

    # Optional: pull a model automatically on rebuild.
    # loadModels = ["qwen3.5:9b"];
  };

  users.users.ollama = {
    isSystemUser = true;
    group = "ollama";
  };
  users.groups.ollama = {};

  # Real folder on the SSD, exposed at a path the sandboxed service can reach.
  fileSystems."/var/lib/ollama-models" = {
    device = "/home/aquarius/Media/SOLID/ollama-models";
    fsType = "none";
    options = [
      "bind"
      "nofail"
      # Make sure the SSD itself is mounted before the bind mount is attempted.
      "x-systemd.requires-mounts-for=/home/aquarius/Media/SOLID"
    ];
  };

  # Ollama must only run on top of the real bind mount. If the SSD or the bind
  # mount is missing, the service fails visibly instead of quietly downloading
  # models onto the root filesystem.
  systemd.services.ollama.unitConfig.RequiresMountsFor = "/var/lib/ollama-models";

  systemd.tmpfiles.rules = [
    "d /home/aquarius/Media/SOLID/ollama-models 0755 ollama ollama -"
  ];

  # Open the port to podman's container networks only, not your LAN.
  networking.firewall.interfaces."podman+".allowedTCPPorts = [11434];
}
