{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    # This is your home-manager configuration file
    ./nvim
    # ./photography
    ./git.nix
    ./ghostty.nix
    ./scripts.nix
    ./packages.nix
    ./stylix.nix
  ];
}
