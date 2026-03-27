{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    tree
    neofetch
    spotify
    nix-output-monitor
    asciiquarium
    cmatrix
    pomodoro
    gparted
    lazygit
    usbimager
    # move to both 
    legcord
    fd
    spotify-cli-linux
    pokemonsay
    ani-cli
    speedtest-cli
    # move and configure 
    ffmpeg-full
    angryipscanner
    #config 
    espeak
    #test 
    quodlibet
    #test 
    xclicker
    poppler-utils
    neo
  ];
}
