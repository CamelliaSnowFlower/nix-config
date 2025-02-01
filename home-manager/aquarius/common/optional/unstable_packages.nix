{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs.untable; [
     nix-search-tv
  ];
}
