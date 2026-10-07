# odysseus.nix
#
# Odysseus (self-hosted AI workspace) on uranus. The module itself lives
# in modules/nixos/odysseus.nix and is exported via the flake's
# nixosModules, so it's pulled in here through the `outputs` specialArg
# rather than touching the uranus nixosSystem in flake.nix.
{outputs, ...}: {
  imports = [outputs.nixosModules.odysseus];

  services.odysseus = {
    enable = true;

    # Pin an immutable tag once you've picked a build that works; `latest`
    # moves on every push to upstream's main branch. Tags are listed at
    # https://github.com/odysseus-dev/odysseus/pkgs/container/odysseus
    # image = "ghcr.io/odysseus-dev/odysseus:1.0.2-7c8070f";

    # Loopback only by default, so it's http://127.0.0.1:7000 on this
    # machine. Set to a LAN / Tailscale address (or "0.0.0.0") to reach it
    # from other devices.
    # bindAddress = "127.0.0.1";

    # API keys / a pre-seeded admin password: KEY=value lines in a root-only
    # file kept outside the nix store.
    # environmentFiles = ["/var/lib/odysseus-secrets.env"];
  };
}
