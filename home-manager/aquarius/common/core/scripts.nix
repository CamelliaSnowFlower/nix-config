{
  config,
  lib,
  pkgs,
  ...
}: {
  # Home-manager Script
  home.packages = with pkgs; [
    (writeShellScriptBin "hms" ''home-manager switch --flake .#$USER@$HOSTNAME |& nom'')
    (writeShellScriptBin "hmsb" ''home-manager switch -b backup --flake .#$USER@$HOSTNAME |& nom'')
  ];
  home.shellAliases = {
    lg = "lazygit";
    hh = "cd ~/Documents/nix-config/";
  };
}
