{
  config,
  lib,
  pkgs,
  ...
}: {
  # hms/sms/hmsb/hh moved to home-manager/common/scripts.nix - shared
  # workflow scripts, not aquarius-specific.
  home.packages = with pkgs; [
    #spotifycli commands with pokemonsay intergration
    (writeShellScriptBin "skip" ''echo "Up Next!" && spotifycli --next && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "rewind" ''echo "Run it Back:" && spotifycli --prev && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "playpause" ''echo ">||" && spotifycli --playpause && spotifycli --song && echo "by" && spotifycli --artist'')
    (writeShellScriptBin "rwp" ''rewind | pokemonsay'')
    (writeShellScriptBin "skp" ''skip | pokemonsay'')
    (writeShellScriptBin "pp" ''playpause | pokemonsay'')
  ];
}
