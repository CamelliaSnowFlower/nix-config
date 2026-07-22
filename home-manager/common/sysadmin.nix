{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.profiles.sysadmin;
in {
  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # nom - piped into by the hms/hmsb scripts below.
      nix-output-monitor

      tree
      fastfetch
      speedtest-cli
      asciiquarium
      cmatrix
      pomodoro

      (writeShellScriptBin "hms" ''home-manager switch --flake .#$USER@$HOSTNAME |& nom'')
      (writeShellScriptBin "sms" ''sudo nixos-rebuild switch --flake .#$HOSTNAME'')
      (writeShellScriptBin "hmsb" ''home-manager switch -b backup --flake .#$USER@$HOSTNAME |& nom'')
      (writeShellScriptBin "hh" ''cd ${config.home.homeDirectory}/Documents/nix-config/'')
    ];
  };
}
