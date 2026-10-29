# Overlays and nixpkgs settings shared by every home-manager user. Kept in one
# place so aquarius and gemini cannot drift apart. The NixOS system-level
# equivalent lives in hosts/common.nix.
{outputs, ...}: {
  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };
}
