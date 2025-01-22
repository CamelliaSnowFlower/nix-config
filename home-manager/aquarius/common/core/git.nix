{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    userName = "AJ";
    userEmail = "camellia.snow.flower@gmail.com";
    extraConfig = {
      init.defaultBranch = "main";
      safe.directory = "/home/aquarius/Documents/nix-config";
    };
  };
}
