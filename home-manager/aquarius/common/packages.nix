{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    tree
    neofetch
    vesktop
    spotify
    nix-output-monitor
    grim
    asciiquarium
    cmatrix
    xorg.xev
    pomodoro
  ];
}
