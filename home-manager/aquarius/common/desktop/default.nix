{config, pkgs, lib, ...}: {
  imports = [
  ./waybar.nix
  ./hyprlock.nix
  ./hyprland.nix
  ];
}
