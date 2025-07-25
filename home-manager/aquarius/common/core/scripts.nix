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
    (writeShellScriptBin "skip" ''echo "Up Next!" && spotifycli --next && spotifycli --song && echo "by" && spotifycli --artist'')
   (writeShellScriptBin "rewind" ''echo "Run it Back:" && spotifycli --prev && spotifycli --song && echo "by" && spotifycli --artist'')
   (writeShellScriptBin "rwp" ''rewind | pokemonsay'')
   (writeShellScriptBin "skp" ''skip | pokemonsay'')
  ];
}
