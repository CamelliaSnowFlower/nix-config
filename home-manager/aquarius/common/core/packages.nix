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
    btop
    # move to both 
    foliate
    # move and change 
    imagemagickBig
    #move 
    prismlauncher
    # move for prismlauncher 
    zulu17
    legcord
    #move 
    openscad
    #move 
    pypy3
    fd
    #move 
    r2modman
    spotify-cli-linux
    pokemonsay
    ani-cli
    speedtest-cli
    # move and configure 
    ffmpeg-full
    angryipscanner
    # move 
    inkscape
    #config 
    espeak
    #move 
    imagej
    #test 
    quodlibet
    #test 
    xclicker
  ];
}
