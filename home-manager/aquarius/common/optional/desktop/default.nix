{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./waybar.nix
    ./hyprlock.nix
    ./hyprland.nix
  ];
  home.packages = with pkgs; [
    grim
    wl-clipboard
  ];
}
