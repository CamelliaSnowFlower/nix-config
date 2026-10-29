# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../common
    ../optional
    ./stylix
    ./ghostty.nix
    ./sticker-notification.nix
  ];

  home = {
    username = "aquarius";
    homeDirectory = "/home/aquarius";
  };

  # Which use-case profiles this user gets - see ../options.nix.
  profiles = {
    photography.enable = true;
    coding.enable = true;
    sysadmin.enable = true;
    desktop.enable = true;
    unstable.enable = true;
  };

  # GNOME autostart - bspwm isn't used, GNOME is.
  xdg.autostart.enable = true;
  xdg.autostart.entries = [
    "${pkgs.obsidian}/share/applications/obsidian.desktop"
    "${pkgs.spotify}/share/applications/spotify.desktop"
  ];

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
