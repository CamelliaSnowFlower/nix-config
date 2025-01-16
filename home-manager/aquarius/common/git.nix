{config, lib, pkgs, ... }:
{
 programs.git = {
  enable = true;
  userName = "AJ";
  userEmail = "camellia.snow.flower@gmail.com";
  extraConfig = {
   init.defaultBranch = "main";
   safe.directory = "/home/aquarius/Documents/nix-config";
  };
 };
 # Home-manager Script
 home.packages = with pkgs; [
  (writeShellScriptBin  "hms" ''home-manager switch --flake .#aquarius@saturn'' )
 ];
 #TODO need to make more scripts for automating git and/or look into lazy git
}
