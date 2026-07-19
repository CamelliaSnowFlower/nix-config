{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    gimp
    darktable
    gphoto2
    digikam
    imagemagickBig
    inkscape
    imagej
  ];
}
