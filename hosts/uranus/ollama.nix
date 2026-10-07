{pkgs, ...}: {
  services.ollama = {
    enable = true;
    package = pkgs.ollama-rocm;
    host = "0.0.0.0";
  };

  networking.firewall.interfaces."podman+".allowedTCPPorts = [11434];
}
