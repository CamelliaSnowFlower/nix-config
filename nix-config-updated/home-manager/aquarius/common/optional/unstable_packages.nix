{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs.unstable; [
    vesktop
    ani-cli
  ];
}
