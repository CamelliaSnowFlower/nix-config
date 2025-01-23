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
    (writeShellScriptBin "home" ''cd /home/$USER/Documents/nix-config/'')
  ];
  #TODO need to make more scripts for automating git and/or look into lazy git
}
