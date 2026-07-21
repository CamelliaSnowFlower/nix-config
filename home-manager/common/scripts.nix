{
  config,
  lib,
  pkgs,
  ...
}: {
  # Nix/home-manager workflow scripts - usable from any user, any host.
  home.packages = with pkgs; [
    (writeShellScriptBin "hms" ''home-manager switch --flake .#$USER@$HOSTNAME |& nom'')
    (writeShellScriptBin "sms" ''sudo nixos-rebuild switch --flake .#$HOSTNAME'')
    (writeShellScriptBin "hmsb" ''home-manager switch -b backup --flake .#$USER@$HOSTNAME |& nom'')
    # Was hardcoded to /home/aquarius/... - fixed the same way as
    # git.nix's safe.directory, so it works for any user.
    (writeShellScriptBin "hh" ''cd ${config.home.homeDirectory}/Documents/nix-config/'')
  ];
}
