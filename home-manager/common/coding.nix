{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.coding;
in {
  # nvim/ carries its own inputs.nvf.homeManagerModules.default import,
  # so it only needs to be pulled in when this profile is actually on.
  imports = lib.optionals cfg.enable [./nvim];

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
