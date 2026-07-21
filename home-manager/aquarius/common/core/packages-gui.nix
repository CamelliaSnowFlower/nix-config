{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    spotify
    gparted
    usbimager
  ];
}
