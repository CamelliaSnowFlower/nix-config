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

  # Pulls the latest pushed config from GitHub over HTTPS - relies on
  # the repo here being the plain HTTPS clone (no SSH key needed).
  home.packages = with pkgs; [
    (writeShellScriptBin "gmu" ''cd ${config.home.homeDirectory}/Documents/nix-config && git pull'')
  ];

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";

  # Fresh install alongside mercury, so this matches its
  # system.stateVersion rather than aquarius's older one.
  home.stateVersion = "26.05";
}
