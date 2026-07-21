{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    tree
    fastfetch
    spotify
    asciiquarium
    cmatrix
    pomodoro
    gparted
    lazygit
    usbimager
    # move and configure 
    ffmpeg-full
    angryipscanner
    poppler-utils
  ];
}
