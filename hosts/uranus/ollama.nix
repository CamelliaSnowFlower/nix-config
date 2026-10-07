{pkgs, ...}: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm; # AMD GPU build
    # Must listen beyond loopback, or the Odysseus container can't reach it.
    host = "0.0.0.0";

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
    options = ["bind" "nofail"];
  };

  systemd.tmpfiles.rules = [
    "d /home/aquarius/Media/SOLID/ollama-models 0755 ollama ollama -"
  ];

  # Open the port to podman's container networks only, not your LAN.
  networking.firewall.interfaces."podman+".allowedTCPPorts = [11434];
}
