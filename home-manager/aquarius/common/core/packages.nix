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
    asciiquarium
    cmatrix
    xorg.xev
    pomodoro
    gparted
    lazygit
    usbimager
    newsboat
    lynx
    btop
    bookworm-unstable
  ];
}
