{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs.unstable; [
    nix-search
  ];
}
