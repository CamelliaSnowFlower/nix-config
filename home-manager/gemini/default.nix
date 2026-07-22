# Home-manager profile for gemini (mercury). Headless admin box - only
# the coding (git + neovim, for editing configs over SSH) and sysadmin
# (nix workflow scripts) profiles are on. photography/desktop/unstable
# all default to false via ../options.nix.
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
    username = "gemini";
    homeDirectory = "/home/gemini";
  };

  profiles = {
    coding.enable = true;
    sysadmin.enable = true;
  };

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";

  # Fresh install alongside mercury, so this matches its
  # system.stateVersion rather than aquarius's older one.
  home.stateVersion = "26.05";
}
