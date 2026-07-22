{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.coding;
in {
  # nvim/'s own programs.nvf is now wrapped in mkIf, so it's safe (and
  # necessary, to avoid the infinite-recursion trap of conditional
  # imports depending on config) to import this unconditionally.
  imports = [./nvim];

  config = lib.mkIf cfg.enable {
    programs.git = {
      enable = true;
      userName = "AJ";
      userEmail = "camellia.snow.flower@gmail.com";
      extraConfig = {
        init.defaultBranch = "main";
        safe.directory = "${config.home.homeDirectory}/Documents/nix-config";
      };
    };

    home.packages = with pkgs; [
      fd
      lazygit
    ];
  };
}
