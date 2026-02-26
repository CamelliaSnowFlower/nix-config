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
    orca-slicer
  ];
}
