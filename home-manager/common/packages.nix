{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    # nom - piped into by the hms/hmsb scripts in ./scripts.nix, so it
    # has to travel with them.
    nix-output-monitor

    # Previously marked "# move to both" in aquarius's packages.nix.
    legcord
    fd
    spotify-cli-linux
    pokemonsay
    speedtest-cli
  ];
}
