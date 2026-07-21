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
      # Was hardcoded to /home/aquarius/... - broke for any other user
      # importing this. config.home.homeDirectory makes it correct
      # for whoever's home-manager config pulls this in.
      safe.directory = "${config.home.homeDirectory}/Documents/nix-config";
    };
  };
}
