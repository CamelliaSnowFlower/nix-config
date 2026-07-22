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
    ./librewolf.nix
    ./stylix
  ];

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

  # startupprograms
  xsession.windowManager.bspwm.enable = true;
  xsession.windowManager.bspwm.startupPrograms = [
    "obsidian"
    "spotify"
  ];

  # Personal Spotify remote-control aliases with pokemonsay
  # integration. Just mine, not a generic "desktop" persona thing, so
  # kept here rather than in ../optional/desktop.nix.
  home.packages = with pkgs; [
    (writeShellScriptBin "skip" ''echo "Up Next!" && spotifycli --next && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "rewind" ''echo "Run it Back:" && spotifycli --prev && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "playpause" ''echo ">||" && spotifycli --playpause && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "rwp" ''rewind | pokemonsay'')
    (writeShellScriptBin "skp" ''skip | pokemonsay'')
    (writeShellScriptBin "pp" ''playpause | pokemonsay'')
  ];

  # Enable home-manager
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "24.11";
}
