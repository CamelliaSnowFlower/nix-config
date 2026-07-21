# Home-manager profile for gemini (mercury). Deliberately minimal -
# no desktop bits, just the shared workflow scripts/packages from
# ../common. Add gemini-specific things here as they come up.
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

  programs.home-manager.enable = true;
  systemd.user.startServices = "sd-switch";

  # Fresh install alongside mercury, so this matches its
  # system.stateVersion rather than aquarius's older one.
  home.stateVersion = "26.05";
}
