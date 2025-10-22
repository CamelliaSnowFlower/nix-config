{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs.unstable; [
    nix-search
    vesktop
    blender
    python313Packages.kokoro
  ];
}
