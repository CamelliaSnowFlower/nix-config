{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.unstable;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs.unstable; [
      ani-cli
      vesktop
    ];
  };
}
