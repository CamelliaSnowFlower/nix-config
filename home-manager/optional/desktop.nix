{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.desktop;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      angryipscanner
      spotify
      gparted
      usbimager
      zotero
    ];
  };
}
