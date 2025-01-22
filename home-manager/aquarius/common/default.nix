{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    # This is your home-manager configuration file
    ./nvim
    ./desktop
    # ./photography
    ./git.nix
    ./ghostty.nix
    ./scripts.nix
    ./packages.nix
  ];
}
