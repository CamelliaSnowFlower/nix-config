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
    (writeShellScriptBin "hh" ''cd /home/aquarius/Documents/nix-config/'')
    (writeShellScriptBin "skip" ''spotifycli --next && spotifycli --song && spotifycli --artist'')
    (writeShellScriptBin "rw" ''spotifycli --prev && spotifycli --song && spotifycli --artist'')
  ];
}
