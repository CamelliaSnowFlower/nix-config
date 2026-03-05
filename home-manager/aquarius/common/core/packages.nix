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
    #del xorg.xev
    pomodoro
    gparted
    lazygit
    usbimager
    newsboat
    # lynx
    # move to both btop
    # move to both foliate
    # move and change imagemagickBig
    #move prismlauncher
    # move for prismlauncher zulu17
    legcord
    #move openscad
    #move pypy3
    fd
    #move r2modman
    spotify-cli-linux
    pokemonsay
    #del artem
    #del ascii-image-converter
    ani-cli
    speedtest-cli
    #del ddgr
    # move and configure ffmpeg-full
    angryipscanner
    # move inkscape
    #del ryubing
    #del nsz
    #config espeak
    #move imagej
    #test quodlibet
    #test xclicker
    #del limo
  ];
}
