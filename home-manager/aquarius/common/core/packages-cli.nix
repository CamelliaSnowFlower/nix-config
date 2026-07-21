{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    asciiquarium
    cmatrix
    pomodoro
  ];
}
