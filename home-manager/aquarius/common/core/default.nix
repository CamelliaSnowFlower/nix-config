{
  pkgs,
  config,
  lib,
  ...
}: {
  imports = [
    # This is your home-manager configuration file
    ./nvim
#./ghostty.nix
    ./scripts.nix
    ./packages-cli.nix
    ./packages-gui.nix
    ./stylix
    ./photography
    ./librewolf.nix
  ];
}
