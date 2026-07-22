{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.photography;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      gimp
      darktable
      gphoto2
      digikam
      imagemagickBig
      inkscape
      imagej
    ];
  };
}
